# Node Provisioning - Discover and provision bare-metal nodes
#
# This discovers hardware via Foreman and triggers OS installation

terraform {
  required_providers {
    foreman = {
      source  = "terraform-coop/foreman"
      version = "~> 1.0"
    }
  }
}

provider "foreman" {
  server_hostname = var.foreman_url
  username        = var.foreman_username
  password        = var.foreman_password
}

# ============================================================================
# DATA SOURCES - Query discovered nodes from Foreman
# ============================================================================

# Get all discovered nodes (not yet provisioned)
data "external" "discovered_nodes" {
  program = ["bash", "${path.module}/scripts/get_discovered_nodes.sh"]

  query = {
    foreman_url      = var.foreman_url
    foreman_username = var.foreman_username
    foreman_password = var.foreman_password
  }
}

# Get hostgroups created in previous phase
data "foreman_hostgroup" "ceph_osd" {
  name = "ceph-osd-nodes"
}

data "foreman_hostgroup" "ceph_mon" {
  name = "ceph-mon-nodes"
}

# ============================================================================
# LOCALS - Process discovered nodes and filter for provisioning
# ============================================================================

locals {
  # Parse discovered nodes JSON
  discovered_raw = jsondecode(data.external.discovered_nodes.result.nodes)

  # Filter nodes suitable for Ceph OSD (based on hardware specs)
  osd_candidates = {
    for node in local.discovered_raw :
    node.mac => node
    if try(node.facts.processors.count, 0) >= 16 &&
       try(node.facts.memory.total_gb, 0) >= 128 &&
       try(node.facts.disks.count, 0) >= 10
  }

  # Filter nodes suitable for Ceph MON (less resource intensive)
  mon_candidates = {
    for node in local.discovered_raw :
    node.mac => node
    if try(node.facts.processors.count, 0) >= 8 &&
       try(node.facts.memory.total_gb, 0) >= 64 &&
       try(node.facts.disks.count, 0) >= 2 &&
       !contains(keys(local.osd_candidates), node.mac)  # Don't overlap with OSDs
  }

  # Take first N nodes for provisioning (configurable)
  nodes_to_provision_osd = {
    for mac, node in local.osd_candidates :
    mac => node
    if index(keys(local.osd_candidates), mac) < var.num_osd_nodes
  }

  nodes_to_provision_mon = {
    for mac, node in local.mon_candidates :
    mac => node
    if index(keys(local.mon_candidates), mac) < var.num_mon_nodes
  }
}

# ============================================================================
# FOREMAN HOSTS - Provision OSD Nodes
# ============================================================================

resource "foreman_host" "ceph_osd" {
  for_each = local.nodes_to_provision_osd

  name = format("ceph-osd-r%02d-u%02d",
    try(each.value.rack_number, 99),
    try(each.value.unit_number, 99)
  )

  hostgroup_id = data.foreman_hostgroup.ceph_osd.id

  # Network configuration
  interfaces_attributes {
    type       = "interface"
    primary    = true
    managed    = true
    provision  = true
    mac        = each.value.mac
    ip         = each.value.ip
    subnet_id  = each.value.subnet_id
  }

  # Trigger build (OS installation)
  build = true

  # Compute attributes (IPMI)
  compute_attributes = {
    start = "1"
  }

  # Additional parameters
  parameters = {
    ipmi_address = try(each.value.ipmi.address, "")
    ipmi_username = "ADMIN"
    discovered_at = timestamp()
  }

  lifecycle {
    ignore_changes = [
      build,  # Don't rebuild on terraform apply
    ]
  }
}

# Wait for provisioning to complete (poll SSH)
resource "null_resource" "wait_for_osd" {
  for_each = foreman_host.ceph_osd

  depends_on = [foreman_host.ceph_osd]

  triggers = {
    host_id = each.value.id
  }

  provisioner "local-exec" {
    command = <<-EOF
      echo "Waiting for ${each.value.name} to complete provisioning..."
      timeout ${var.provision_timeout} bash -c '
        while ! ssh -o StrictHostKeyChecking=no \
                    -o ConnectTimeout=5 \
                    -o BatchMode=yes \
                    root@${each.value.ip} "echo ready" 2>/dev/null; do
          echo "Still waiting for ${each.value.name}..."
          sleep 30
        done
      '
      echo "${each.value.name} is ready!"
    EOF
  }
}

# ============================================================================
# FOREMAN HOSTS - Provision MON Nodes
# ============================================================================

resource "foreman_host" "ceph_mon" {
  for_each = local.nodes_to_provision_mon

  name = format("ceph-mon-r%02d-u%02d",
    try(each.value.rack_number, 99),
    try(each.value.unit_number, 99)
  )

  hostgroup_id = data.foreman_hostgroup.ceph_mon.id

  interfaces_attributes {
    type       = "interface"
    primary    = true
    managed    = true
    provision  = true
    mac        = each.value.mac
    ip         = each.value.ip
    subnet_id  = each.value.subnet_id
  }

  build = true

  compute_attributes = {
    start = "1"
  }

  parameters = {
    ipmi_address = try(each.value.ipmi.address, "")
    ipmi_username = "ADMIN"
    discovered_at = timestamp()
  }

  lifecycle {
    ignore_changes = [build]
  }
}

resource "null_resource" "wait_for_mon" {
  for_each = foreman_host.ceph_mon

  depends_on = [foreman_host.ceph_mon]

  triggers = {
    host_id = each.value.id
  }

  provisioner "local-exec" {
    command = <<-EOF
      timeout ${var.provision_timeout} bash -c '
        while ! ssh -o StrictHostKeyChecking=no \
                    -o ConnectTimeout=5 \
                    -o BatchMode=yes \
                    root@${each.value.ip} "echo ready" 2>/dev/null; do
          sleep 30
        done
      '
    EOF
  }
}

# ============================================================================
# INVENTORY EXPORT - For Ansible
# ============================================================================

resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../../ansible/inventory/terraform_hosts.yml"

  content = yamlencode({
    all = {
      children = {
        ceph_osd = {
          hosts = {
            for name, host in foreman_host.ceph_osd :
            name => {
              ansible_host = host.ip
              ansible_user = "root"
              ansible_ssh_private_key_file = var.ssh_private_key_path
              ipmi_address = try(host.parameters.ipmi_address, "")
              hostgroup = "ceph-osd-nodes"
            }
          }
        }
        ceph_mon = {
          hosts = {
            for name, host in foreman_host.ceph_mon :
            name => {
              ansible_host = host.ip
              ansible_user = "root"
              ansible_ssh_private_key_file = var.ssh_private_key_path
              ipmi_address = try(host.parameters.ipmi_address, "")
              hostgroup = "ceph-mon-nodes"
            }
          }
        }
      }
    }
  })
}

# ============================================================================
# OUTPUTS
# ============================================================================

output "osd_nodes" {
  description = "Provisioned OSD nodes"
  value = {
    for name, host in foreman_host.ceph_osd :
    name => {
      ip       = host.ip
      mac      = host.interfaces_attributes[0].mac
      hostname = host.name
      state    = "provisioned"
    }
  }
}

output "mon_nodes" {
  description = "Provisioned MON nodes"
  value = {
    for name, host in foreman_host.ceph_mon :
    name => {
      ip       = host.ip
      mac      = host.interfaces_attributes[0].mac
      hostname = host.name
      state    = "provisioned"
    }
  }
}

output "ansible_inventory_path" {
  value = local_file.ansible_inventory.filename
}

output "provision_summary" {
  value = {
    osd_count = length(foreman_host.ceph_osd)
    mon_count = length(foreman_host.ceph_mon)
    total     = length(foreman_host.ceph_osd) + length(foreman_host.ceph_mon)
  }
}
