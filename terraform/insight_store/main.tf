terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
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

resource "google_project_iam_member" "store_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.insight_store.email}"
}

# ── Pub/Sub: whisper-completion pull subscription ─────────────────────────────

resource "google_cloud_run_v2_service_iam_member" "pubsub_invoker" {
  project  = var.project_id
  location = var.region
  name     = "insight-store"
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.insight_store.email}"
}

resource "google_pubsub_subscription" "store_whisper_completion_sub" {
  name  = "store-whisper-completion-sub"
  topic = "projects/${var.project_id}/topics/whisper-completion"

  ack_deadline_seconds = 60

  push_config {
    push_endpoint = "https://insight-store-b5mjto3bjq-uc.a.run.app/pubsub/whisper-completion"

    oidc_token {
      service_account_email = google_service_account.insight_store.email
    }
  }
}

# ── Pub/Sub: token-completion push subscription ───────────────────────────────

resource "google_pubsub_subscription" "store_token_completion_sub" {
  name  = "store-token-completion-sub"
  topic = "projects/${var.project_id}/topics/token-completion"

  ack_deadline_seconds = 60

  push_config {
    push_endpoint = "https://insight-store-b5mjto3bjq-uc.a.run.app/pubsub/token-completion"

    oidc_token {
      service_account_email = google_service_account.insight_store.email
    }
  }
}

# ── BigQuery tables ───────────────────────────────────────────────────────────

resource "google_bigquery_table" "token_completion" {
  dataset_id          = "insight_metadata"
  table_id            = "token_completion"
  deletion_protection = false

  schema = jsonencode([
    { name = "video_id",    type = "STRING",    mode = "REQUIRED", description = "Unique identifier for the video" },
    { name = "status",      type = "STRING",    mode = "REQUIRED", description = "Processing status: completed or failed" },
    { name = "token_count", type = "INTEGER",   mode = "REQUIRED", description = "Number of tokens produced" },
    { name = "gcs_out",     type = "STRING",    mode = "REQUIRED", description = "GCS path to the token file" },
    { name = "timestamp",   type = "TIMESTAMP", mode = "REQUIRED", description = "ISO 8601 timestamp of when tokenization completed" },
  ])
}

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
