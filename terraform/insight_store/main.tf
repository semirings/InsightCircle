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
  image                              = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}/insight-store:${var.image_tag}"
  whisper_completion_subscription_id = "projects/${var.project_id}/subscriptions/whisper-completion-sub"
}

resource "google_service_account" "insight_store" {
  account_id   = "insight-store-sa"
  display_name = "InsightStore Service Account"
}

resource "google_project_iam_member" "store_bq" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.insight_store.email}"
}

resource "google_project_iam_member" "store_gcs" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.insight_store.email}"
}

resource "google_project_iam_member" "store_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.insight_store.email}"
}

# ── Pub/Sub: whisper-completion subscription ──────────────────────────────────

resource "google_pubsub_subscription" "whisper_completion_sub" {
  name  = "whisper-completion-sub"
  topic = "whisper-completion"

  ack_deadline_seconds = 60
}

# ── BigQuery: whisper_completion table ────────────────────────────────────────

resource "google_bigquery_table" "whisper_completion" {
  dataset_id          = "insight_metadata"
  table_id            = "whisper_completion"
  deletion_protection = false

  schema = jsonencode([
    { name = "video_id",    type = "STRING",    mode = "REQUIRED", description = "Unique identifier for the video" },
    { name = "status",      type = "STRING",    mode = "REQUIRED", description = "Processing status: completed, pending, or failed" },
    { name = "bucket",      type = "STRING",    mode = "REQUIRED", description = "GCS bucket where the output is stored" },
    { name = "output_path", type = "STRING",    mode = "REQUIRED", description = "Path within the bucket to the transcription output file" },
    { name = "timestamp",   type = "TIMESTAMP", mode = "REQUIRED", description = "ISO 8601 timestamp of when the result was recorded" },
  ])
}

# ── Cloud Run ─────────────────────────────────────────────────────────────────

resource "google_cloud_run_v2_service" "insight_store" {
  name     = "insight-store"
  location = var.region

  template {
    service_account = google_service_account.insight_store.email

    containers {
      image = local.image

      ports {
        container_port = 5203
      }

      env {
        name  = "PYTHONUNBUFFERED"
        value = "1"
      }

      env {
        name  = "WHISPER_COMPLETION_SUBSCRIPTION"
        value = local.whisper_completion_subscription_id
      }

      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
      }
    }
  }
}

output "insight_store_url" {
  value = google_cloud_run_v2_service.insight_store.uri
}
