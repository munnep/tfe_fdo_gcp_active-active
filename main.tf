resource "google_compute_network" "tfe_vpc" {
  name                    = "${var.tag_prefix}-vpc"
  auto_create_subnetworks = false
}


resource "google_compute_subnetwork" "tfe_subnet" {
  name          = "${var.tag_prefix}-public1"
  ip_cidr_range = cidrsubnet(var.vnet_cidr, 8, 1)
  network       = google_compute_network.tfe_vpc.self_link
}

resource "google_compute_router" "tfe_router" {
  name    = "${var.tag_prefix}-router"
  region  = google_compute_subnetwork.tfe_subnet.region
  network = google_compute_network.tfe_vpc.self_link
}

# resource "google_compute_router" "router" {
#   name    = "my-router"
#   region  = google_compute_subnetwork.tfe_subnet.region
#   network = google_compute_network.tfe_vpc.id

#   bgp {
#     asn = 64514
#   }
# }

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


resource "google_compute_instance" "tfe" {
  name         = var.tag_prefix
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
      nat_ip = google_compute_address.tfe-public-ipc.address
    }
  }

  metadata = {
    "ssh-keys" = "ubuntu:${var.public_key}"
  }

  depends_on = [google_compute_subnetwork.tfe_subnet]

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

resource "google_compute_address" "tfe-public-ipc" {
  name         = "${var.tag_prefix}-public-ip"
  address_type = "EXTERNAL"
}

# resource "google_compute_disk" "compute_disk_swap" {
#   name = "${var.tag_prefix}-swap-disk"
#   type = "pd-ssd"
#   size = "10"
#   zone = "${var.gcp_region}-a"
# }

# resource "google_compute_disk" "compute_disk_docker" {
#   name = "${var.tag_prefix}-docker-disk"
#   type = "pd-ssd"
#   size = "20"
#   zone = "${var.gcp_region}-a"
# }

# resource "google_compute_disk" "compute_disk_tfe_data" {
#   name = "${var.tag_prefix}-tfe-data-disk"
#   type = "pd-ssd"
#   size = "40"
#   zone = "${var.gcp_region}-a"
# }

# resource "google_compute_attached_disk" "swap" {
#   disk     = google_compute_disk.compute_disk_swap.id
#   instance = google_compute_instance.tfe.id
# }

# resource "google_compute_attached_disk" "docker" {
#   disk     = google_compute_disk.compute_disk_docker.id
#   instance = google_compute_instance.tfe.id
# }

# resource "google_compute_attached_disk" "tfe_data" {
#   disk     = google_compute_disk.compute_disk_tfe_data.id
#   instance = google_compute_instance.tfe.id
# }

resource "google_compute_firewall" "default" {
  name    = "test-firewall"
  network = google_compute_network.tfe_vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22", "443", "5432", "8201", "6379"]
  }

  source_ranges = ["0.0.0.0/0"]
}

resource "google_storage_bucket" "tfe-bucket" {
  name          = "${var.tag_prefix}-bucket"
  location      = var.gcp_location
  force_destroy = true

  public_access_prevention    = "enforced"
  uniform_bucket_level_access = true
}

resource "google_compute_global_address" "private_ip_address" {
  # provider = google-beta

  name          = "tfe-vpc-internal"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.tfe_vpc.id
}

resource "google_service_networking_connection" "private_vpc_connection" {
  # provider = google-beta

  network                 = google_compute_network.tfe_vpc.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_ip_address.name]

  deletion_policy = "ABANDON"
}


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
