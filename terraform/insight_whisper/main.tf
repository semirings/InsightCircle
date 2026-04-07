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
  image                       = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}/insight-whisper:${var.image_tag}"
  whisper_completion_topic    = "projects/${var.project_id}/topics/whisper-completion"
  whisper_input_subscription  = "projects/${var.project_id}/subscriptions/whisper-input-sub"
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
}

# ── Pub/Sub: whisper-completion topic ─────────────────────────────────────────

resource "google_pubsub_topic" "whisper_completion" {
  name = "whisper-completion"
}

# ── Cloud Run ─────────────────────────────────────────────────────────────────

resource "google_cloud_run_v2_service" "insight_whisper" {
  name     = "insight-whisper"
  location = var.region

  template {
    service_account = google_service_account.insight_whisper.email

    containers {
      image = local.image

      ports {
        container_port = 8080
      }

      env {
        name  = "WHISPER_MODEL"
        value = var.whisper_model
      }

      env {
        name  = "WHISPER_COMPLETION_TOPIC"
        value = local.whisper_completion_topic
      }

      env {
        name  = "WHISPER_INPUT_SUBSCRIPTION"
        value = local.whisper_input_subscription
      }

      resources {
        limits = {
          cpu    = "4"
          memory = "4Gi"
        }
        startup_cpu_boost = true
      }
    }

    # Transcription can be slow — allow up to 15 min
    timeout = "900s"
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
