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
  image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}/insight-token:${var.image_tag}"
}

resource "google_service_account" "insight_token" {
  account_id   = "insight-token-sa"
  display_name = "InsightToken Service Account"
}

resource "google_project_iam_member" "token_gcs" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.insight_token.email}"
}

resource "google_cloud_run_v2_service" "insight_token" {
  name     = "insight-token"
  location = var.region

  template {
    service_account = google_service_account.insight_token.email

    containers {
      image = local.image

      ports {
        container_port = 8080
      }

      env {
        name  = "SPACY_MODEL"
        value = var.spacy_model
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "1Gi"
        }
      }
    }
  }
}

output "insight_token_url" {
  value = google_cloud_run_v2_service.insight_token.uri
}
