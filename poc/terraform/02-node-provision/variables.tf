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

variable "ssh_public_key" {
  description = "SSH public key for root access to provisioned nodes"
  type        = string
}

variable "ssh_private_key_path" {
  description = "Path to SSH private key for Ansible"
  type        = string
  default     = "~/.ssh/id_rsa"
}
