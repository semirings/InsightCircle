terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ── Service account ───────────────────────────────────────────────────────────

resource "google_service_account" "insight_ingest" {
  account_id   = "insight-ingest-sa"
  display_name = "InsightIngest Service Account"
}

resource "google_project_iam_member" "ingest_gcs" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.insight_ingest.email}"
}

resource "google_project_iam_member" "ingest_bq" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.insight_ingest.email}"
}

resource "google_project_iam_member" "ingest_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.insight_ingest.email}"
}

# ── Pub/Sub: ingest-trigger topic + push subscription ────────────────────────

resource "google_pubsub_topic" "ingest_trigger" {
  name = "ingest-trigger"
}

resource "google_cloud_run_v2_service_iam_member" "pubsub_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.insight_ingest.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.insight_ingest.email}"
}

resource "google_pubsub_subscription" "ingest_trigger_sub" {
  name  = "ingest-trigger-sub"
  topic = google_pubsub_topic.ingest_trigger.id

  ack_deadline_seconds = 600   # 10 min; phase 1 can take several minutes

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.insight_ingest.uri}/pubsub/ingest"

    oidc_token {
      service_account_email = google_service_account.insight_ingest.email
    }
  }
}

# ── Cloud Run service ─────────────────────────────────────────────────────────

resource "google_cloud_run_v2_service" "insight_ingest" {
  name     = "insight-ingest"
  location = var.region

  template {
    service_account = google_service_account.insight_ingest.email

    timeout = "3600s"   # up to 1 h; yt-dlp + API batches can be slow

    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}/insight-ingest:latest"

      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }

      env {
        name = "YOUTUBE_API_KEY"
        value_source {
          secret_key_ref {
            secret  = "youtube-api-key"
            version = "latest"
          }
        }
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
      }
    }
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "ingest_service_url" {
  value = google_cloud_run_v2_service.insight_ingest.uri
}

output "ingest_trigger_topic" {
  value = google_pubsub_topic.ingest_trigger.id
}
