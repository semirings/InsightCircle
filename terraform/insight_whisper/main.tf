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
  image                    = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}/insight-whisper:${var.image_tag}"
  whisper_completion_topic = "projects/${var.project_id}/topics/whisper-completion"
}

resource "google_service_account" "insight_whisper" {
  account_id   = "insight-whisper-sa"
  display_name = "InsightWhisper Service Account"
}

resource "google_project_iam_member" "whisper_gcs" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.insight_whisper.email}"
}

resource "google_project_iam_member" "whisper_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.insight_whisper.email}"
}

resource "google_project_iam_member" "whisper_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.insight_whisper.email}"
}

# ── Pub/Sub: whisper-input topic & subscription ───────────────────────────────

resource "google_pubsub_topic" "whisper_input" {
  name = "whisper-input"
}

resource "google_pubsub_subscription" "whisper_input_sub" {
  name  = "whisper-input-sub"
  topic = google_pubsub_topic.whisper_input.name

  # Transcription can take up to 15 min; use the maximum supported deadline
  ack_deadline_seconds = 600

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.insight_whisper.uri}/pubsub/whisper-input"

    oidc_token {
      service_account_email = google_service_account.insight_whisper.email
    }
  }
}

resource "google_cloud_run_v2_service_iam_member" "pubsub_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.insight_whisper.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.insight_whisper.email}"
}

# ── Pub/Sub: whisper-completion topic ─────────────────────────────────────────

resource "google_pubsub_topic" "whisper_completion" {
  name = "whisper-completion"
}

# ── Cloud Run ─────────────────────────────────────────────────────────────────

resource "google_cloud_run_v2_service" "insight_whisper" {
  name     = "insight-whisper"
  location = "us-central1"

  template {
    containers {
      image = "us-central1-docker.pkg.dev/creator-d4m-2026-1774038056/insight-repo/insight-whisper:latest"

      # This is the fix for the KeyError
      env {
        name  = "WHISPER_INPUT_SUBSCRIPTION"
        value = "projects/creator-d4m-2026-1774038056/subscriptions/whisper-input-sub"
      }

      # Your code likely needs these next
      env {
        name  = "WHISPER_COMPLETION_TOPIC"
        value = "projects/creator-d4m-2026-1774038056/topics/whisper-completion"
      }

      env {
        name  = "GCP_PROJECT_ID"
        value = "creator-d4m-2026-1774038056"
      }
      
      # Recommended: Set memory to at least 2Gi for Whisper
      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
      }
    }
  }
}

output "insight_whisper_url" {
  value = google_cloud_run_v2_service.insight_whisper.uri
}

output "whisper_input_topic" {
  value = google_pubsub_topic.whisper_input.name
}

output "whisper_completion_topic" {
  value = google_pubsub_topic.whisper_completion.name
}
