terraform {
  required_version = ">= 1.5.0"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

locals {
  backend_tag = "${var.name_prefix}-backend"

  default_backend_service_id = var.prod_weight > 0 ? google_compute_backend_service.prod.id : google_compute_backend_service.contingency.id

  active_weighted_backend_services = concat(
    var.prod_weight > 0 ? [
      {
        backend_service = google_compute_backend_service.prod.id
        weight          = var.prod_weight
      }
    ] : [],
    var.contingency_weight > 0 ? [
      {
        backend_service = google_compute_backend_service.contingency.id
        weight          = var.contingency_weight
      }
    ] : []
  )

  prod_startup_script = <<-EOF
    #!/bin/bash
    set -euo pipefail

    mkdir -p /opt/web
    cat > /opt/web/index.html <<'HTML'
    Bienvenido al Servicio Principal - Versión Producción
    HTML

    cat > /etc/systemd/system/simple-web.service <<'UNIT'
    [Unit]
    Description=Simple web server for Terraform project
    After=network-online.target

    [Service]
    Type=simple
    WorkingDirectory=/opt/web
    ExecStart=/usr/bin/python3 -m http.server 80 --bind 0.0.0.0
    Restart=always
    RestartSec=3

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable --now simple-web.service
  EOF

  contingency_startup_script = <<-EOF
    #!/bin/bash
    set -euo pipefail

    mkdir -p /opt/web
    cat > /opt/web/index.html <<'HTML'
    Error 503 - Sitio en Mantenimiento Programado
    HTML

    cat > /etc/systemd/system/simple-web.service <<'UNIT'
    [Unit]
    Description=Simple web server for Terraform project
    After=network-online.target

    [Service]
    Type=simple
    WorkingDirectory=/opt/web
    ExecStart=/usr/bin/python3 -m http.server 80 --bind 0.0.0.0
    Restart=always
    RestartSec=3

    [Install]
    WantedBy=multi-user.target
    UNIT

    systemctl daemon-reload
    systemctl enable --now simple-web.service
  EOF
}

resource "google_project_service" "serviceusage" {
  project            = var.project_id
  service            = "serviceusage.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "compute" {
  project            = var.project_id
  service            = "compute.googleapis.com"
  disable_on_destroy = false

  depends_on = [google_project_service.serviceusage]
}

resource "google_compute_network" "vpc" {
  name                    = "${var.name_prefix}-vpc"
  auto_create_subnetworks = false

  depends_on = [google_project_service.compute]
}

resource "google_compute_subnetwork" "subnet" {
  name          = "${var.name_prefix}-subnet"
  ip_cidr_range = "10.10.0.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
}

resource "google_compute_instance" "prod" {
  name         = "${var.name_prefix}-prod-vm"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = [local.backend_tag]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
  }

  metadata_startup_script = replace(local.prod_startup_script, "\r\n", "\n")
}

resource "google_compute_instance" "contingency" {
  name         = "${var.name_prefix}-contingency-vm"
  machine_type = "e2-micro"
  zone         = var.zone
  tags         = [local.backend_tag]

  boot_disk {
    initialize_params {
      image = "debian-cloud/debian-12"
      size  = 10
      type  = "pd-balanced"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.subnet.id
  }

  metadata_startup_script = replace(local.contingency_startup_script, "\r\n", "\n")
}

resource "google_compute_instance_group" "prod" {
  name      = "${var.name_prefix}-prod-ig"
  zone      = var.zone
  instances = [google_compute_instance.prod.self_link]

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_instance_group" "contingency" {
  name      = "${var.name_prefix}-contingency-ig"
  zone      = var.zone
  instances = [google_compute_instance.contingency.self_link]

  named_port {
    name = "http"
    port = 80
  }
}

resource "google_compute_health_check" "http" {
  name                = "${var.name_prefix}-http-health"
  check_interval_sec  = 5
  timeout_sec         = 5
  healthy_threshold   = 2
  unhealthy_threshold = 2

  http_health_check {
    port         = 80
    request_path = "/"
  }
}

resource "google_compute_firewall" "allow_health_checks" {
  name          = "${var.name_prefix}-allow-health-checks"
  network       = google_compute_network.vpc.id
  direction     = "INGRESS"
  priority      = 1000
  source_ranges = ["130.211.0.0/22", "35.191.0.0/16"]
  target_tags   = [local.backend_tag]

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }
}

resource "google_compute_backend_service" "prod" {
  name                  = "${var.name_prefix}-prod-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.http.id]
  session_affinity      = "NONE"

  backend {
    group           = google_compute_instance_group.prod.self_link
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_backend_service" "contingency" {
  name                  = "${var.name_prefix}-contingency-backend"
  protocol              = "HTTP"
  port_name             = "http"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  timeout_sec           = 30
  health_checks         = [google_compute_health_check.http.id]
  session_affinity      = "NONE"

  backend {
    group           = google_compute_instance_group.contingency.self_link
    balancing_mode  = "UTILIZATION"
    capacity_scaler = 1.0
  }
}

resource "google_compute_url_map" "traffic" {
  name            = "${var.name_prefix}-url-map"
  default_service = local.default_backend_service_id

  lifecycle {
    precondition {
      condition     = var.prod_weight + var.contingency_weight > 0
      error_message = "La suma de prod_weight y contingency_weight debe ser mayor que 0: al menos un servicio debe recibir trafico."
    }
  }

  host_rule {
    hosts        = ["*"]
    path_matcher = "all"
  }

  path_matcher {
    name            = "all"
    default_service = local.default_backend_service_id

    route_rules {
      priority = 1

      match_rules {
        prefix_match = "/"
      }

      route_action {
        dynamic "weighted_backend_services" {
          for_each = local.active_weighted_backend_services
          iterator = backend

          content {
            backend_service = backend.value.backend_service
            weight          = backend.value.weight
          }
        }
      }
    }
  }
}

resource "google_compute_global_address" "lb_ip" {
  name       = "${var.name_prefix}-lb-ip"
  ip_version = "IPV4"
}

resource "google_compute_target_http_proxy" "http" {
  name    = "${var.name_prefix}-http-proxy"
  url_map = google_compute_url_map.traffic.id
}

resource "google_compute_global_forwarding_rule" "http" {
  name                  = "${var.name_prefix}-http-rule"
  ip_protocol           = "TCP"
  load_balancing_scheme = "EXTERNAL_MANAGED"
  port_range            = "80-80"
  target                = google_compute_target_http_proxy.http.id
  ip_address            = google_compute_global_address.lb_ip.id
}
