terraform {
  required_version = ">= 1.6.0"

  required_providers {
    foreman = {
      source  = "terraform-coop/foreman"
      version = ">= 0.1"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

provider "foreman" {
  server_hostname = var.foreman_hostname
  server_protocol = var.foreman_protocol

  client_username      = var.foreman_username
  client_password      = var.foreman_password
  client_tls_insecure  = var.foreman_insecure

  provider_loglevel = "INFO"
  provider_logfile  = "terraform-provider-foreman.log"
}

# Load inventory
locals {
  inventory = yamldecode(file("${path.root}/../../inventory.yml"))
  
  # Create maps by role
  osd_nodes = {
    for server in local.inventory.servers :
    server.hostname => server
    if server.role == "osd"
  }
  
  mon_nodes = {
    for server in local.inventory.servers :
    server.hostname => server
    if server.role == "mon"
  }
  
  all_nodes = merge(local.osd_nodes, local.mon_nodes)
}

# Get hostgroups from previous step
data "foreman_hostgroup" "ceph_osd" {
  title = "Ceph OSD Nodes"
}

data "foreman_hostgroup" "ceph_mon" {
  title = "Ceph MON Nodes"
}

# Power on servers via IPMI for discovery
resource "null_resource" "ipmi_power_on" {
  for_each = local.all_nodes

  provisioner "local-exec" {
    command = <<-EOT
      ../../scripts/ipmi-power.sh \
        ${each.value.ipmi.address} \
        ${each.value.ipmi.username} \
        ${each.value.ipmi.password} \
        on
    EOT
  }

  triggers = {
    server = each.key
  }
}

# Wait for discovery (manual step - user must verify in Foreman UI)
resource "null_resource" "wait_for_discovery" {
  depends_on = [null_resource.ipmi_power_on]

  provisioner "local-exec" {
    command = <<-EOT
      echo "============================================"
      echo "Servers are booting for discovery..."
      echo "============================================"
      echo ""
      echo "Please verify in Foreman UI:"
      echo "  Hosts -> Discovered Hosts"
      echo ""
      echo "Expected ${length(local.all_nodes)} servers:"
      %{ for hostname, server in local.all_nodes ~}
      echo "  - ${hostname} (MAC: ${server.network.provisioning_mac})"
      %{ endfor ~}
      echo ""
      echo "Press ENTER when all servers are discovered..."
      read confirmation
    EOT

    interpreter = ["/bin/bash", "-c"]
  }
}

# Provision hosts
resource "foreman_host" "ceph_osd" {
  for_each = local.osd_nodes
  
  depends_on = [null_resource.wait_for_discovery]

  name         = each.value.hostname
  hostgroup_id = data.foreman_hostgroup.ceph_osd.id
  
  # Network configuration
  interfaces_attributes {
    type = "interface"
    primary = true
    managed = true
    provision = true
    
    mac      = each.value.network.provisioning_mac
    ip       = each.value.network.management_ip
    name     = "eth0"
  }
  
  # Enable build mode (triggers OS installation)
  build = true
  
  parameters = {
    role                 = "osd"
    rack                 = each.value.rack
    unit                 = each.value.unit
    ceph_public_ip       = each.value.network.ceph_public_ip
    ceph_cluster_ip      = each.value.network.ceph_cluster_ip
    ssh_authorized_keys  = var.ssh_public_key
  }

  lifecycle {
    ignore_changes = [
      build  # Don't rebuild on subsequent applies
    ]
  }
}

resource "foreman_host" "ceph_mon" {
  for_each = local.mon_nodes
  
  depends_on = [null_resource.wait_for_discovery]

  name         = each.value.hostname
  hostgroup_id = data.foreman_hostgroup.ceph_mon.id
  
  interfaces_attributes {
    type = "interface"
    primary = true
    managed = true
    provision = true
    
    mac      = each.value.network.provisioning_mac
    ip       = each.value.network.management_ip
    name     = "eth0"
  }
  
  build = true
  
  parameters = {
    role                = "mon"
    rack                = each.value.rack
    unit                = each.value.unit
    ceph_public_ip      = each.value.network.ceph_public_ip
    ssh_authorized_keys = var.ssh_public_key
  }

  lifecycle {
    ignore_changes = [
      build
    ]
  }
}

# Wait for SSH to become available
resource "null_resource" "wait_for_ssh" {
  for_each = local.all_nodes
  
  depends_on = [
    foreman_host.ceph_osd,
    foreman_host.ceph_mon
  ]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for ${each.key} (${each.value.network.management_ip}) to be accessible via SSH..."
      timeout=3600  # 60 minutes
      elapsed=0
      
      while ! nc -z ${each.value.network.management_ip} 22 2>/dev/null; do
        if [ $elapsed -ge $timeout ]; then
          echo "ERROR: Timeout waiting for ${each.key}"
          exit 1
        fi
        echo "Still waiting... ($elapsed seconds elapsed)"
        sleep 30
        elapsed=$((elapsed + 30))
      done
      
      echo "✓ ${each.key} is accessible via SSH"
    EOT

    interpreter = ["/bin/bash", "-c"]
  }
}

# Generate Ansible inventory
resource "local_file" "ansible_inventory" {
  depends_on = [null_resource.wait_for_ssh]
  
  filename = "${path.root}/../../ansible/inventory/hosts.yml"
  
  content = yamlencode({
    all = {
      children = {
        ceph_osd = {
          hosts = {
            for hostname, server in local.osd_nodes :
            hostname => {
              ansible_host = server.network.management_ip
              rack         = server.rack
              unit         = server.unit
              ipmi_address = server.ipmi.address
              ceph_public_ip   = server.network.ceph_public_ip
              ceph_cluster_ip  = server.network.ceph_cluster_ip
            }
          }
        }
        ceph_mon = {
          hosts = {
            for hostname, server in local.mon_nodes :
            hostname => {
              ansible_host = server.network.management_ip
              rack         = server.rack
              unit         = server.unit
              ipmi_address = server.ipmi.address
              ceph_public_ip = server.network.ceph_public_ip
            }
          }
        }
      }
      vars = {
        ansible_user = "root"
        ansible_ssh_private_key_file = var.ssh_private_key_path
        ansible_python_interpreter = "/usr/bin/python3"
      }
    }
  })
}

output "provisioned_nodes" {
  value = {
    osd = {
      for k, v in foreman_host.ceph_osd :
      k => {
        id     = v.id
        ip     = local.osd_nodes[k].network.management_ip
        status = "provisioned"
      }
    }
    mon = {
      for k, v in foreman_host.ceph_mon :
      k => {
        id     = v.id
        ip     = local.mon_nodes[k].network.management_ip
        status = "provisioned"
      }
    }
  }
}

output "ansible_inventory_path" {
  value = local_file.ansible_inventory.filename
}
