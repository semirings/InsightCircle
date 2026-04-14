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
  image                    = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}/insight-token:${var.image_tag}"
  whisper_completion_topic = "projects/${var.project_id}/topics/whisper-completion"
  token_completion_topic   = "projects/${var.project_id}/topics/token-completion"
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

resource "google_project_iam_member" "token_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.insight_token.email}"
}

resource "google_project_iam_member" "token_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.insight_token.email}"
}

resource "google_pubsub_topic" "token_completion" {
  name = "token-completion"
}

resource "google_cloud_run_v2_service_iam_member" "pubsub_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.insight_token.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.insight_token.email}"
}

# ── Pub/Sub: whisper-completion subscription ──────────────────────────────────

resource "google_pubsub_subscription" "whisper_completion_sub" {
  name  = "whisper-completion-sub"
  topic = local.whisper_completion_topic

  ack_deadline_seconds = 60

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.insight_token.uri}/pubsub/whisper-completion"

    oidc_token {
      service_account_email = google_service_account.insight_token.email
    }
  }
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

      env {
        name  = "TOKEN_COMPLETION_TOPIC"
        value = local.token_completion_topic
      }

      env {
        name  = "AA_INGEST_TOPIC"
        value = "projects/${var.project_id}/topics/aa-ingest"
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

output "token_completion_subscription" {
  value = google_pubsub_subscription.whisper_completion_sub.name
}
