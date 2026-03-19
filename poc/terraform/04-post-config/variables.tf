# Variables for Post-Configuration

variable "playbook_version" {
  description = "Version/hash to trigger playbook re-run"
  type        = string
  default     = "1.0"
}

variable "ansible_verbose" {
  description = "Enable Ansible verbose output (-vvv)"
  type        = bool
  default     = false
}

variable "ansible_check_mode" {
  description = "Run Ansible in check mode (dry-run)"
  type        = bool
  default     = false
}

variable "run_validation" {
  description = "Run validation tests after configuration"
  type        = bool
  default     = true
}

variable "validate_only" {
  description = "Only run validation, skip configuration"
  type        = bool
  default     = false
}

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
