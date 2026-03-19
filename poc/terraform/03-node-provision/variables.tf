# Variables for Node Provisioning

variable "foreman_url" {
  description = "Foreman server URL"
  type        = string
}

variable "foreman_username" {
  description = "Foreman admin username"
  type        = string
  sensitive   = true
}

variable "foreman_password" {
  description = "Foreman admin password"
  type        = string
  sensitive   = true
}

variable "num_osd_nodes" {
  description = "Number of OSD nodes to provision"
  type        = number
  default     = 3
}

variable "num_mon_nodes" {
  description = "Number of MON nodes to provision"
  type        = number
  default     = 3
}

variable "provision_timeout" {
  description = "Timeout for provisioning (seconds)"
  type        = number
  default     = 1800  # 30 minutes
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for provisioned nodes"
  type        = string
  default     = "~/.ssh/id_rsa"
}

variable "auto_approve_osd" {
  description = "Automatically approve OSD nodes based on hardware criteria"
  type        = bool
  default     = true
}

variable "auto_approve_mon" {
  description = "Automatically approve MON nodes based on hardware criteria"
  type        = bool
  default     = true
}
