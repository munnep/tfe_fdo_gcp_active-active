# default network creation
resource "google_compute_network" "tfe_vpc" {
  name                    = "${var.tag_prefix}-vpc"
  auto_create_subnetworks = false
}

# public subnet
resource "google_compute_subnetwork" "tfe_subnet_public1" {
  name          = "${var.tag_prefix}-public1"
  ip_cidr_range = cidrsubnet(var.vnet_cidr, 8, 1)
  network       = google_compute_network.tfe_vpc.self_link
}

# subnet to put the instances without a public IP
resource "google_compute_subnetwork" "tfe_subnet_private1" {
  name          = "${var.tag_prefix}-private1"
  ip_cidr_range = cidrsubnet(var.vnet_cidr, 8, 11)
  network       = google_compute_network.tfe_vpc.self_link
}

# routing for the NAT
resource "google_compute_router" "tfe_router" {
  name    = "${var.tag_prefix}-router"
  region  = google_compute_subnetwork.tfe_subnet_private1.region
  network = google_compute_network.tfe_vpc.self_link
}

# NAT gateway
resource "google_compute_router_nat" "nat" {
  name                               = "my-router-nat"
  router                             = google_compute_router.tfe_router.name
  region                             = google_compute_router.tfe_router.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# client server
resource "google_compute_instance" "tfe-client" {
  name         = "${var.tag_prefix}-client"
  machine_type = "e2-medium"
  zone         = "${var.gcp_region}-a"

  boot_disk {
    initialize_params {
      image = "ubuntu-2204-jammy-v20240207"
    }
  }

  // Local SSD disk
  # scratch_disk {
  #   interface = "NVME"
  # }

  network_interface {
    network    = "${var.tag_prefix}-vpc"
    subnetwork = "${var.tag_prefix}-public1"

    access_config {
      // Ephemeral public IP
      nat_ip = google_compute_address.tfe-client-public.address
    }
  }

  metadata = {
    "ssh-keys" = "ubuntu:${var.public_key}"
  }

  depends_on = [google_compute_subnetwork.tfe_subnet_public1]

  lifecycle {
    ignore_changes = [attached_disk]
  }

  service_account {
    # Google recommends custom service accounts that have cloud-platform scope and permissions granted via IAM Roles.
    email  = google_service_account.service_account.email
    scopes = ["cloud-platform"]
  }
  # on_instance_stop_action {
  #   discard_local_ssd = true
  # }
  allow_stopping_for_update = true
}

# public ip address for the client server
resource "google_compute_address" "tfe-client-public" {
  name         = "${var.tag_prefix}-client-public-ip"
  address_type = "EXTERNAL"
}

# default router on the network to work
resource "google_compute_firewall" "default" {
  name    = "${var.tag_prefix}-firewall"
  network = google_compute_network.tfe_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "443", "5432", "8201", "6379"]
  }

  source_ranges = ["0.0.0.0/0"]
}

# bucket to storage TFE files on
resource "google_storage_bucket" "tfe-bucket" {
  name          = "${var.tag_prefix}-bucket"
  location      = var.gcp_location
  force_destroy = true

  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
}

# private network range where the Redis and PostgreSQL services will be stored
resource "google_compute_global_address" "private_ip_address" {
  # provider = google-beta

  name          = "tfe-vpc-internal"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.tfe_vpc.id
}

# to make sure the redis and postgresql can get certain information
resource "google_service_networking_connection" "private_vpc_connection" {
  # provider = google-beta

  network                 = google_compute_network.tfe_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]

  deletion_policy = "ABANDON"
}



# to make sure instances can connect to the bucket without authentication
resource "google_project_iam_binding" "example_storage_admin_binding" {
  project = var.gcp_project
  role    = "roles/storage.admin"

  members = [
    "serviceAccount:${google_service_account.service_account.email}"
  ]
}

# doing it all on bucket permissions
resource "google_service_account" "service_account" {
  account_id   = "${var.tag_prefix}-bucket-test"
  display_name = "${var.tag_prefix}-bucket-test"
  project      = var.gcp_project
}

resource "google_service_account_key" "tfe_bucket" {
  service_account_id = google_service_account.service_account.name
}

resource "google_storage_bucket_iam_member" "member-object" {
  bucket = google_storage_bucket.tfe-bucket.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

resource "google_storage_bucket_iam_member" "member-bucket" {
  bucket = google_storage_bucket.tfe-bucket.name
  role   = "roles/storage.legacyBucketReader"
  member = "serviceAccount:${google_service_account.service_account.email}"
}

# Postgresql environment
resource "google_sql_database_instance" "instance" {
  provider = google-beta

  name             = "${var.tag_prefix}-database"
  region           = var.gcp_region
  database_version = "POSTGRES_15"

  depends_on = [google_service_networking_connection.private_vpc_connection]

  settings {
    tier = "db-g1-small" ## possible issue in size
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = google_compute_network.tfe_vpc.id
      enable_private_path_for_google_cloud_services = true
    }
  }
  deletion_protection = false
}

resource "google_sql_database" "tfe-db" {
  # provider = google-beta
  name     = "tfe"
  instance = google_sql_database_instance.instance.name
}

resource "google_sql_user" "tfeadmin" {
  # provider = google-beta
  name            = "admin-tfe"
  instance        = google_sql_database_instance.instance.name
  password        = var.rds_password
  deletion_policy = "ABANDON"
}

resource "google_redis_instance" "cache" {
  name           = "memory-cache"
  memory_size_gb = 1

  authorized_network = google_compute_network.tfe_vpc.id
  auth_enabled       = false
  connect_mode       = "PRIVATE_SERVICE_ACCESS"
  depends_on         = [google_service_networking_connection.private_vpc_connection]

}
