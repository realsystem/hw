terraform {
  required_version = ">= 1.6.0"

  required_providers {
    foreman = {
      source  = "terraform-coop/foreman"
      version = ">= 0.1"
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

# Note: Using hardcoded IDs for mock API compatibility
# In real Foreman, use data sources to lookup existing resources
# data "foreman_architecture" "x86_64" { name = "x86_64" }
# data "foreman_operatingsystem" "debian12" { name = "Debian" }

locals {
  architecture_id    = 1  # x86_64 in mock API
  operatingsystem_id = 1  # Debian 12 in mock API
}

# Provisioning Network
resource "foreman_subnet" "provisioning" {
  name             = "Provisioning Network"
  network          = var.provisioning_network
  mask             = var.provisioning_netmask
  gateway          = var.provisioning_gateway
  dns_primary      = var.dns_primary
  dns_secondary    = var.dns_secondary
  ipam             = "DHCP"
  boot_mode        = "DHCP"
  network_type     = "IPv4"
  
  from = var.dhcp_range_start
  to   = var.dhcp_range_end
  
  vlanid = var.provisioning_vlan
}

# Management Network  
resource "foreman_subnet" "management" {
  name          = "Management Network"
  network       = var.management_network
  mask          = var.management_netmask
  gateway       = var.management_gateway
  dns_primary   = var.dns_primary
  dns_secondary = var.dns_secondary
  ipam          = "None"
  network_type  = "IPv4"
  
  vlanid = var.management_vlan
}

# Partition Table for OSD Nodes
resource "foreman_partitiontable" "ceph_osd" {
  name      = "Ceph OSD Partition Table"
  os_family = "Debian"
  
  layout = <<-EOT
d-i partman-auto/disk string /dev/sda
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic

d-i partman-auto/expert_recipe string \
  boot-root :: \
    512 512 512 ext4 \
      $primary{ } $bootable{ } \
      method{ format } format{ } \
      use_filesystem{ } filesystem{ ext4 } \
      mountpoint{ /boot } \
    . \
    100% 8192 -1 ext4 \
      method{ format } format{ } \
      use_filesystem{ } filesystem{ ext4 } \
      mountpoint{ / } \
    .

d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true

# Leave all other disks unpartitioned for Ceph OSDs
EOT
}

# Partition Table for MON Nodes
resource "foreman_partitiontable" "ceph_mon" {
  name      = "Ceph MON Partition Table"
  os_family = "Debian"
  
  layout = <<-EOT
d-i partman-auto/disk string /dev/sda
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic

d-i partman-auto/expert_recipe string \
  boot-root :: \
    512 512 512 ext4 \
      $primary{ } $bootable{ } \
      method{ format } format{ } \
      use_filesystem{ } filesystem{ ext4 } \
      mountpoint{ /boot } \
    . \
    100% 4096 -1 ext4 \
      method{ format } format{ } \
      use_filesystem{ } filesystem{ ext4 } \
      mountpoint{ / } \
    .

d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
EOT
}

# Hostgroup for OSD Nodes
resource "foreman_hostgroup" "ceph_osd" {
  name = "Ceph OSD Nodes"

  architecture_id    = local.architecture_id
  operatingsystem_id = local.operatingsystem_id
  ptable_id          = foreman_partitiontable.ceph_osd.id
  subnet_id          = foreman_subnet.provisioning.id

  parameters = {
    role                 = "osd"
    ceph_public_network  = var.ceph_public_network
    ceph_cluster_network = var.ceph_cluster_network
  }
}

# Hostgroup for MON Nodes
resource "foreman_hostgroup" "ceph_mon" {
  name = "Ceph MON Nodes"

  architecture_id    = local.architecture_id
  operatingsystem_id = local.operatingsystem_id
  ptable_id          = foreman_partitiontable.ceph_mon.id
  subnet_id          = foreman_subnet.provisioning.id

  parameters = {
    role                 = "mon"
    ceph_public_network  = var.ceph_public_network
  }
}

output "hostgroups" {
  value = {
    osd = {
      id   = foreman_hostgroup.ceph_osd.id
      name = foreman_hostgroup.ceph_osd.name
    }
    mon = {
      id   = foreman_hostgroup.ceph_mon.id
      name = foreman_hostgroup.ceph_mon.name
    }
  }
}

output "subnets" {
  value = {
    provisioning = {
      id      = foreman_subnet.provisioning.id
      network = foreman_subnet.provisioning.network
    }
    management = {
      id      = foreman_subnet.management.id
      network = foreman_subnet.management.network
    }
  }
}
