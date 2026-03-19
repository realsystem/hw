variable "foreman_hostname" {
  description = "Foreman server hostname or IP (without protocol)"
  type        = string
  default     = "localhost:3000"
}

variable "foreman_protocol" {
  description = "Foreman server protocol (http or https)"
  type        = string
  default     = "http"
}

variable "foreman_username" {
  description = "Foreman admin username"
  type        = string
  default     = "admin"
}

variable "foreman_password" {
  description = "Foreman admin password"
  type        = string
  sensitive   = true
  default     = "changeme123"
}

variable "foreman_insecure" {
  description = "Skip SSL verification"
  type        = string
  default     = "true"
}

# Network Configuration
variable "provisioning_network" {
  description = "Provisioning network address"
  type        = string
  default     = "10.50.0.0"
}

variable "provisioning_netmask" {
  description = "Provisioning network netmask"
  type        = string
  default     = "255.255.0.0"
}

variable "provisioning_gateway" {
  description = "Provisioning network gateway"
  type        = string
  default     = "10.50.0.1"
}

variable "provisioning_vlan" {
  description = "Provisioning VLAN ID"
  type        = number
  default     = 50
}

variable "management_network" {
  description = "Management network address"
  type        = string
  default     = "10.10.0.0"
}

variable "management_netmask" {
  description = "Management network netmask"
  type        = string
  default     = "255.255.0.0"
}

variable "management_gateway" {
  description = "Management network gateway"
  type        = string
  default     = "10.10.0.1"
}

variable "management_vlan" {
  description = "Management VLAN ID"
  type        = number
  default     = 10
}

variable "dhcp_range_start" {
  description = "DHCP range start"
  type        = string
  default     = "10.50.3.100"
}

variable "dhcp_range_end" {
  description = "DHCP range end"
  type        = string
  default     = "10.50.15.254"
}

variable "dns_primary" {
  description = "Primary DNS server"
  type        = string
  default     = "10.5.0.1"
}

variable "dns_secondary" {
  description = "Secondary DNS server"
  type        = string
  default     = "10.5.0.2"
}

# Ceph Configuration
variable "ceph_public_network" {
  description = "Ceph public network CIDR"
  type        = string
  default     = "10.20.0.0/16"
}

variable "ceph_cluster_network" {
  description = "Ceph cluster network CIDR"
  type        = string
  default     = "10.30.0.0/16"
}
