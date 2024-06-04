# resource "google_compute_health_check" "autohealing" {
#   name                = "autohealing-health-check"
#   check_interval_sec  = 5
#   timeout_sec         = 
#   healthy_threshold   = 2
#   unhealthy_threshold = 10

#   http_health_check {
#     request_path = "/_health_check"
#     port         = "443"
#   }
# }



resource "google_compute_instance_template" "default" {
  name        = "tfe-server-template"
  description = "This template is used to create a TFE server instances."

  tags = ["foo", "bar"]

  # labels = {
  #   environment = "dev"
  # }

  instance_description = "description assigned to instances"
  machine_type         = "n2-standard-8"
  can_ip_forward       = false

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  // Create a new boot disk from an image
  disk {
    source_image      = "ubuntu-2204-jammy-v20240207"
    auto_delete       = true
    boot              = true
  }

  network_interface {
    network    = "${var.tag_prefix}-vpc"
    subnetwork = "${var.tag_prefix}-public1"
  }

  metadata = {
    "ssh-keys" = "ubuntu:${var.public_key}"
    "user-data" = templatefile("${path.module}/scripts/cloudinit_tfe_server.yaml", {
      tag_prefix        = var.tag_prefix
      dns_hostname      = var.dns_hostname
      tfe_password      = var.tfe_password
      dns_zonename      = var.dns_zonename
      tfe_release       = var.tfe_release
      tfe_license       = var.tfe_license
      certificate_email = var.certificate_email
      full_chain        = base64encode("${acme_certificate.certificate.certificate_pem}${acme_certificate.certificate.issuer_pem}")
      private_key_pem   = base64encode(lookup(acme_certificate.certificate, "private_key_pem"))
      pg_dbname         = google_sql_database.tfe-db.name
      pg_address        = google_sql_database_instance.instance.private_ip_address
      rds_password      = var.rds_password
      tfe_bucket        = "${var.tag_prefix}-bucket"
      region            = var.gcp_region
      gcp_project       = var.gcp_project
    })
  }

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.service_account.email
    scopes = ["cloud-platform"]
  }
}

resource "google_compute_instance_group_manager" "appserver" {
  name = "tfe-instance-group"

  base_instance_name = "tfe-instances"
  zone               = "${var.gcp_region}-a"

  version {
    instance_template  = google_compute_instance_template.default.self_link_unique
  }

  # all_instances_config {
  #   metadata = {
  #     metadata_key = "metadata_value"
  #   }
  #   labels = {
  #     label_key = "label_value"
  #   }
  # }

  # target_pools = [google_compute_target_pool.appserver.id]
  target_size  = 1

  named_port {
    name = "https"
    port = 443
  }

  # auto_healing_policies {
  #   health_check      = google_compute_health_check.autohealing.id
  #   initial_delay_sec = 300
  # }

  depends_on = [ google_compute_subnetwork.tfe_subnet ]
}