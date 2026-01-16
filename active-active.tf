data "google_compute_image" "ubuntu" {
  family  = "ubuntu-2404-lts-amd64"
  project = "ubuntu-os-cloud"
}

data "google_compute_image" "redhat" {
  family  = "rhel-9"
  project = "rhel-cloud"
}

locals {
  os_user = var.tfe_os == "redhat" ? "cloud-user" : "ubuntu"
}


resource "google_compute_instance_template" "tfe" {
  name_prefix = var.tag_prefix
  description = "This template is used to create a TFE server instances."

  tags = ["${var.tag_prefix}"]


  instance_description = "${var.tag_prefix}-instance"
  machine_type         = "n2-standard-8"
  can_ip_forward       = false

  scheduling {
    automatic_restart   = true
    on_host_maintenance = "MIGRATE"
  }

  // Create a new boot disk from an image
  disk {
    source_image = var.tfe_os == "ubuntu" ? data.google_compute_image.ubuntu.self_link : data.google_compute_image.redhat.self_link
    auto_delete  = true
    boot         = true
  }

  network_interface {
    network    = "${var.tag_prefix}-vpc"
    subnetwork = "${var.tag_prefix}-private1"
  }

  metadata = {
    "ssh-keys" = "${local.os_user}:${var.public_key}"
    "user-data" = templatefile("${path.module}/scripts/cloudinit_tfe_server_${var.tfe_os}.yaml", {
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
      redis_host        = google_redis_instance.cache.host
    })
  }

  metadata_startup_script = var.tfe_os == "redhat" ? file("${path.module}/scripts/startup_wrapper_redhat.sh") : null


  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.service_account.email
    scopes = ["cloud-platform"]
  }
}

# autoscaler settings
resource "google_compute_region_autoscaler" "tfe" {
  name   = "${var.tag_prefix}-autoscaler"
  region = var.gcp_region
  target = google_compute_region_instance_group_manager.tfe.id

  autoscaling_policy {
    max_replicas    = var.max_replicas
    min_replicas    = var.min_replicas
    cooldown_period = 300

    cpu_utilization {
      target = 0.8
    }
  }
}


resource "google_compute_region_instance_group_manager" "tfe" {
  name = "tfe-instance-group"

  base_instance_name = "tfe-instances"
  region             = var.gcp_region

  version {
    instance_template = google_compute_instance_template.tfe.self_link_unique
  }

  named_port {
    name = "https"
    port = 443
  }

  depends_on = [google_compute_subnetwork.tfe_subnet_public1]

  lifecycle {
    create_before_destroy = true
  }
}
