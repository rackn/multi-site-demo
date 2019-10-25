# Configure the Linode provider
variable "linode_token" {
  type = string
}

provider "linode" {
  token = var.linode_token
}
# Regions ca-central, us-central, us-west, us-southeast, us-east

resource "linode_instance" "drp_manager" {
  image  = "linode/centos7"
  label  = "rackn-manager-demo"
  region = "us-central"
  type   = "g6-standard-2"
  root_pass      = "r0cketsk8ts"

  stackscript_id = "604895"
  stackscript_data = {
    "drp_version" = "stable"
    "drp_password" = "r0cketsk8ts"
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