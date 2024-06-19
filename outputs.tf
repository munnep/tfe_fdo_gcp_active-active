# output "ssh_tfe_server" {
#   value = [
#     for k in data.aws_instances.foo.private_ips : "ssh -J ubuntu@${var.dns_hostname}-client.${var.dns_zonename} ubuntu@${k}"
#   ]
# }

output "tfe_client" {
  value = "ssh ubuntu@${var.dns_hostname}-client.${var.dns_zonename}"
}

output "tfe_appplication" {
  value = "https://${var.dns_hostname}.${var.dns_zonename}"
}




# data "google_compute_region_instance_group" "group" {
#   name = "tfe-instance-group"
# }

# locals {
#   tfe_instances = data.google_compute_region_instance_group.group.instances[*].instance
# }

# data "google_compute_instance" "appserver" {
#   for_each = toset(local.tfe_instances)
#   self_link  = each.value
# }


# output "ssh_tfe_server" {
#   value = [for key, value in data.google_compute_instance.appserver : "ssh -J ubuntu@${var.dns_hostname}-client.${var.dns_zonename} ubuntu@${value.network_interface[0].network_ip}"]
# }