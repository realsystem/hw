# Post-Configuration - Run Ansible on provisioned nodes
#
# This applies Ceph-ready baseline configuration after OS installation

terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.0"
    }
  }
}

# ============================================================================
# DATA SOURCES - Get provisioned nodes from previous phase
# ============================================================================

data "terraform_remote_state" "provisioning" {
  backend = "local"

  config = {
    path = "../03-node-provision/terraform.tfstate"
  }
}

locals {
  ansible_inventory = data.terraform_remote_state.provisioning.outputs.ansible_inventory_path
  osd_nodes         = data.terraform_remote_state.provisioning.outputs.osd_nodes
  mon_nodes         = data.terraform_remote_state.provisioning.outputs.mon_nodes
}

# ============================================================================
# ANSIBLE EXECUTION - Apply Ceph baseline configuration
# ============================================================================

resource "null_resource" "ansible_ceph_baseline" {
  # Trigger on inventory changes
  triggers = {
    inventory_content = filemd5(local.ansible_inventory)
    playbook_version  = var.playbook_version
  }

  depends_on = [data.terraform_remote_state.provisioning]

  provisioner "local-exec" {
    command = <<-EOF
      echo "Running Ansible playbook: ceph_baseline.yml"

      cd ${path.module}/../../ansible

      ansible-playbook \
        -i ${local.ansible_inventory} \
        playbooks/ceph_baseline.yml \
        ${var.ansible_verbose ? "-vvv" : ""} \
        ${var.ansible_check_mode ? "--check" : ""} \
        --extra-vars "validate_only=${var.validate_only}"
    EOF
  }
}

# ============================================================================
# VALIDATION - Run post-configuration tests
# ============================================================================

resource "null_resource" "validation" {
  count = var.run_validation ? 1 : 0

  depends_on = [null_resource.ansible_ceph_baseline]

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command = <<-EOF
      cd ${path.module}/../../ansible

      ansible-playbook \
        -i ${local.ansible_inventory} \
        playbooks/validate.yml \
        --extra-vars "output_format=json" \
        > ${path.module}/validation_results.json
    EOF
  }
}

# ============================================================================
# VALIDATION RESULTS - Parse and output
# ============================================================================

data "local_file" "validation_results" {
  count      = var.run_validation ? 1 : 0
  depends_on = [null_resource.validation]
  filename   = "${path.module}/validation_results.json"
}

locals {
  validation_data = var.run_validation ? jsondecode(data.local_file.validation_results[0].content) : {}
}

# ============================================================================
# CEPH ANSIBLE INVENTORY GENERATION
# ============================================================================

resource "local_file" "ceph_ansible_inventory" {
  filename = "${path.module}/../../ceph-ansible/inventory/hosts.yml"

  content = templatefile("${path.module}/templates/ceph_inventory.yml.tpl", {
    osd_nodes = local.osd_nodes
    mon_nodes = local.mon_nodes
    ceph_public_network  = var.ceph_public_network
    ceph_cluster_network = var.ceph_cluster_network
  })
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "configuration_status" {
  value = {
    ansible_completed = null_resource.ansible_ceph_baseline.id != ""
    inventory_path    = local.ansible_inventory
    nodes_configured  = length(local.osd_nodes) + length(local.mon_nodes)
  }
}

output "validation_results" {
  value = var.run_validation ? local.validation_data : null
}

output "validation_summary" {
  value = var.run_validation ? {
    total_tests  = try(length(local.validation_data.results), 0)
    passed       = try(length([for r in local.validation_data.results : r if r.status == "passed"]), 0)
    failed       = try(length([for r in local.validation_data.results : r if r.status == "failed"]), 0)
    success_rate = try(
      length([for r in local.validation_data.results : r if r.status == "passed"]) /
      length(local.validation_data.results) * 100, 0
    )
  } : null
}

output "ceph_inventory_path" {
  value       = local_file.ceph_ansible_inventory.filename
  description = "Path to ceph-ansible inventory file"
}

output "next_steps" {
  value = <<-EOF
    Configuration complete! Next steps:

    1. Review validation results:
       terraform output validation_summary

    2. Deploy Ceph cluster:
       cd ../../ceph-ansible
       ansible-playbook -i ${local_file.ceph_ansible_inventory.filename} site.yml

    3. Verify Ceph cluster health:
       ssh ${try(values(local.osd_nodes)[0].hostname, "node")} ceph -s

    Nodes configured: ${length(local.osd_nodes) + length(local.mon_nodes)}
    - OSD nodes: ${length(local.osd_nodes)}
    - MON nodes: ${length(local.mon_nodes)}
  EOF
}
