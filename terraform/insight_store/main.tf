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

# ── Pub/Sub: ontology-completion push subscription ───────────────────────────

resource "google_pubsub_subscription" "store_ontology_completion_sub" {
  name  = "store-ontology-completion-sub"
  topic = "projects/${var.project_id}/topics/ontology-completion"

  ack_deadline_seconds = 60

  push_config {
    push_endpoint = "https://insight-store-b5mjto3bjq-uc.a.run.app/pubsub/ontology-completion"

    oidc_token {
      service_account_email = google_service_account.insight_store.email
    }
  }
}

# ── Pub/Sub: aa-ingest pull subscription ─────────────────────────────────────

resource "google_pubsub_subscription" "aa_ingest_sub" {
  name  = "aa-ingest-sub"
  topic = "projects/${var.project_id}/topics/aa-ingest"

  ack_deadline_seconds       = 60
  message_retention_duration = "604800s"  # 7 days
}

# ── BigQuery AA tables (rcvs triple format) ──────────────────────────────────

locals {
  aa_table_schema = jsonencode([
    { name = "video_id",  type = "STRING",    mode = "REQUIRED", description = "Video identifier (anchor)" },
    { name = "row",       type = "STRING",    mode = "REQUIRED", description = "Assoc row key" },
    { name = "col",       type = "STRING",    mode = "REQUIRED", description = "Assoc column key" },
    { name = "val",       type = "STRING",    mode = "REQUIRED", description = "Assoc value" },
    { name = "timestamp", type = "TIMESTAMP", mode = "REQUIRED", description = "Ingestion timestamp" },
  ])
}

resource "google_bigquery_table" "tokens" {
  dataset_id          = "insight_metadata"
  table_id            = "tokens"
  deletion_protection = false
  schema              = local.aa_table_schema
}

resource "google_bigquery_table" "ontology" {
  dataset_id          = "insight_metadata"
  table_id            = "ontology"
  deletion_protection = false
  schema              = local.aa_table_schema
}

resource "google_bigquery_table" "ontology_gpc" {
  dataset_id          = "insight_metadata"
  table_id            = "ontology_gpc"
  deletion_protection = false
  schema              = local.aa_table_schema
}

resource "google_bigquery_table" "ontology_meta" {
  dataset_id          = "insight_metadata"
  table_id            = "ontology_meta"
  deletion_protection = false
  schema              = local.aa_table_schema
}

resource "google_bigquery_table" "ontology_meta_gpc" {
  dataset_id          = "insight_metadata"
  table_id            = "ontology_meta_gpc"
  deletion_protection = false
  schema              = local.aa_table_schema
}

resource "google_bigquery_table" "logs" {
  dataset_id          = "insight_metadata"
  table_id            = "logs"
  deletion_protection = false
  # Reuses the project-wide AA schema. video_id holds the log event_id (UUIDv7).
  schema              = local.aa_table_schema
}

resource "google_bigquery_table" "ontology_comments" {
  dataset_id          = "insight_metadata"
  table_id            = "ontology_comments"
  deletion_protection = false
  schema              = local.aa_table_schema
}

resource "google_bigquery_table" "ontology_comments_gpc" {
  dataset_id          = "insight_metadata"
  table_id            = "ontology_comments_gpc"
  deletion_protection = false
  schema              = local.aa_table_schema
}

resource "google_bigquery_table" "ontology_transcripts" {
  dataset_id          = "insight_metadata"
  table_id            = "ontology_transcripts"
  deletion_protection = false
  schema              = local.aa_table_schema
}

resource "google_bigquery_table" "ontology_transcripts_gpc" {
  dataset_id          = "insight_metadata"
  table_id            = "ontology_transcripts_gpc"
  deletion_protection = false
  schema              = local.aa_table_schema
}

resource "google_bigquery_table" "ontology_threads" {
  dataset_id          = "insight_metadata"
  table_id            = "ontology_threads"
  deletion_protection = false
  schema              = local.aa_table_schema
}

resource "google_bigquery_table" "ontology_threads_gpc" {
  dataset_id          = "insight_metadata"
  table_id            = "ontology_threads_gpc"
  deletion_protection = false
  schema              = local.aa_table_schema
}

# ── BigQuery video tags table ────────────────────────────────────────────────

resource "google_bigquery_table" "video_tags" {
  dataset_id          = "insight_metadata"
  table_id            = "video_tags"
  deletion_protection = false

  schema = jsonencode([
    { name = "video_id",    type = "STRING",    mode = "REQUIRED", description = "YouTube video identifier" },
    { name = "tag",         type = "STRING",    mode = "REQUIRED", description = "Tag assigned by the video creator (lowercased)" },
    { name = "job_id",      type = "STRING",    mode = "REQUIRED", description = "Ingest job that produced this row" },
    { name = "ingested_at", type = "TIMESTAMP", mode = "REQUIRED", description = "When this row was written" },
  ])
}

# ── BigQuery quota log table ──────────────────────────────────────────────────

resource "google_bigquery_table" "quota_log" {
  dataset_id          = "insight_metadata"
  table_id            = "quota_log"
  deletion_protection = false

  schema = jsonencode([
    { name = "date",                type = "DATE",      mode = "REQUIRED", description = "UTC date of the ingest run" },
    { name = "job_id",              type = "STRING",    mode = "REQUIRED", description = "Ingest job identifier" },
    { name = "keywords_searched",   type = "INTEGER",   mode = "NULLABLE", description = "Number of keywords searched" },
    { name = "search_calls",        type = "INTEGER",   mode = "NULLABLE", description = "Number of search.list API calls" },
    { name = "video_calls",         type = "INTEGER",   mode = "NULLABLE", description = "Number of videos.list API calls" },
    { name = "comment_calls",       type = "INTEGER",   mode = "NULLABLE", description = "Number of commentThreads.list API calls" },
    { name = "total_units",         type = "INTEGER",   mode = "NULLABLE", description = "Total YouTube Data API quota units consumed" },
    { name = "videos_fetched",      type = "INTEGER",   mode = "NULLABLE", description = "Videos collected before dedup/filter" },
    { name = "videos_written",      type = "INTEGER",   mode = "NULLABLE", description = "Videos written after all filters" },
    { name = "timestamp",           type = "TIMESTAMP", mode = "REQUIRED", description = "When this row was written" },
  ])
}

# ── BigQuery completion event tables ─────────────────────────────────────────

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
