terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

locals {
  image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}/insight-calc:${var.image_tag}"
}

# ── Service account ───────────────────────────────────────────────────────────

resource "google_service_account" "insight_calc" {
  account_id   = "insight-calc-sa"
  display_name = "InsightCalc Service Account"
}

# BQ read-only + ability to run query jobs
resource "google_project_iam_member" "calc_bq_viewer" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.insight_calc.email}"
}

resource "google_project_iam_member" "calc_bq_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.insight_calc.email}"
}

resource "google_project_iam_member" "calc_pubsub_pub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.insight_calc.email}"
}

# Allow Cloud Run Jobs to be executed under this SA
resource "google_project_iam_member" "calc_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.insight_calc.email}"
}

# ── Cloud Run Service (ad-hoc queries) ───────────────────────────────────────

resource "google_cloud_run_v2_service" "insight_calc" {
  name     = "insight-calc"
  location = var.region

  template {
    service_account = google_service_account.insight_calc.email

    containers {
      image = local.image

      ports {
        container_port = 8080
      }

      env {
        name  = "BQ_PROJECT"
        value = var.project_id
      }

      env {
        name  = "BQ_DATASET"
        value = var.bq_dataset
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
      }
    }

    # Keep one warm instance to avoid Julia cold-start on ad-hoc queries
    scaling {
      min_instance_count = 1
      max_instance_count = 3
    }
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "insight_calc_url" {
  value = google_cloud_run_v2_service.insight_calc.uri
}
