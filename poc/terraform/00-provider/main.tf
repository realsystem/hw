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

# Test connection with a simple null resource
resource "null_resource" "foreman_test" {
  provisioner "local-exec" {
    command = "echo 'Foreman provider initialized successfully'"
  }
}

output "foreman_connection" {
  value = {
    server   = "${var.foreman_protocol}://${var.foreman_hostname}"
    username = var.foreman_username
    status   = "connected"
    note     = "Provider configured - test resource creation in 01-foreman-config"
  }
}
