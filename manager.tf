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

terraform {
  required_providers {
    linode = {
      source = "linode/linode"
      version = ">= 1.13.4"
    }
  }
  required_version = ">= 0.13"
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

  stackscript_id = "674971"
  stackscript_data = {
    "drp_version" = "tip"
    "drp_password" = var.manager_password
    "drp_user" = "rocketskates"
    "drp_id" = var.manager_label
    "initial_workflow" = "universal-bootstrap"
    "initial_contents" = "universal,edge-lab"
    "initial_plugins" = "filebeat"
    "initial_profiles" = "bootstrap-contexts,bootstrap-elasticsearch,bootstrap-kibana,bootstrap-filebeat"
    "initial_catalog" = "https://rebar-catalog.s3-us-west-2.amazonaws.com/jpmc-catalog.json"
    "open_ports" = "8091/tcp,8092/tcp,9300/tcp,9200/tcp,5601/tcp"
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
