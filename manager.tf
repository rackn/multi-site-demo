# Configure the Linode provider
variable "linode_token" {
  type      = string
}

variable "manager_label" {
  type      = string
}

# Regions ca-central, us-central, us-west, us-southeast, us-east
variable "manager_region" {
  type      = string
}

variable "manager_image" {
  type      = string
}

variable "manager_type" {
  type      = string
}

variable "manager_password" {
  type      = string
}

provider "linode" {
  token     = var.linode_token
}

resource "linode_instance" "drp_manager" {
  image     = var.manager_image
  label     = var.manager_label
  region    = var.manager_region
  type      = var.manager_type
  root_pass = var.manager_password

  stackscript_id = "604895"
  stackscript_data = {
    "drp_version" = "stable"
    "drp_password" = var.manager_password
    "drp_id" = "rackn-manager-demo"
  }
}

output "drp_ip" {
  value       = linode_instance.drp_manager.ip_address
  description = "The IP of DRP"
}

output "drp_manager" {
  value       = "https://${linode_instance.drp_manager.ip_address}:8092"
  description = "The URL of DRP"
}
