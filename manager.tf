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

variable "cluster_prefix" {
  type      = string
}

variable "ssh_key" {
  type      = string
}

resource "linode_instance" "drp_manager" {
  image     = var.manager_image
  label     = var.manager_label
  region    = var.manager_region
  type      = var.manager_type
  root_pass = var.manager_password
  tags      = [ "cluster-${var.cluster_prefix}"]
  authorized_keys = ["${var.ssh_key}"]

  stackscript_id = "657412"
  stackscript_data = {
    "drp_version" = "tip"
    "drp_password" = var.manager_password
    "drp_id" = var.manager_label
    "initial_workflow" = "bootstrap-advanced"
    "initial_contents" = "drp-community-content, task-library, edge-lab, dev-library"
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
