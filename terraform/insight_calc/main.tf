terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_service_account" "insight_calc" {
  account_id   = "insight-calc-sa"
  display_name = "InsightCalc Service Account"
}

resource "google_project_iam_member" "calc_gcs" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.insight_calc.email}"
}

resource "google_project_iam_member" "calc_bq" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.insight_calc.email}"
}

resource "google_project_iam_member" "calc_pubsub_pub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.insight_calc.email}"
}

resource "google_compute_instance" "insight_dev_node" {
  name         = "insight-dev-node"
  machine_type = var.machine_type
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 50
    }
  }

  network_interface {
    network = "default"
    access_config {}   # ephemeral public IP
  }

  service_account {
    email  = google_service_account.insight_calc.email
    scopes = ["cloud-platform"]
  }

  metadata_startup_script = <<-EOT
    #!/usr/bin/env bash
    set -euo pipefail

    # Install juliaup
    curl -fsSL https://install.julialang.org | sh -s -- -y
    export PATH="$HOME/.juliaup/bin:$PATH"

    # Clone repo and start service
    mkdir -p /home/gcr/populi.Wk/InsightCircle
    systemctl daemon-reload
    systemctl enable insight-calc
    systemctl start insight-calc
  EOT

  tags = ["insight-calc"]
}

output "insight_calc_ip" {
  value = google_compute_instance.insight_dev_node.network_interface[0].access_config[0].nat_ip
}
