resource "google_compute_region_health_check" "tfe" {
  name = "tfe-check"

  description         = "tfe-check"
  healthy_threshold   = 2
  check_interval_sec  = 5
  unhealthy_threshold = 10

  https_health_check {
    port         = 443
    request_path = "/_health_check"
  }
}

resource "google_compute_region_backend_service" "tfe" {
  name                  = "test"
  region                = var.gcp_region
  protocol              = "TCP"
  load_balancing_scheme = "EXTERNAL"
  timeout_sec           = 30
  health_checks         = [google_compute_region_health_check.tfe.id]

  backend {
    group          = google_compute_region_instance_group_manager.tfe.instance_group
    balancing_mode = "CONNECTION"
  }

  # perhaps needed
  #   locality_lb_policy = "MAGLEV"

  connection_draining_timeout_sec = 300
}

resource "google_compute_forwarding_rule" "tfe" {
  name                  = "test"
  description           = "test"
  region                = var.gcp_region
  depends_on            = [google_compute_subnetwork.tfe_subnet_private1]
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL"
  ports                 = ["443"]
  network_tier          = "PREMIUM"
  backend_service       = google_compute_region_backend_service.tfe.id
}
