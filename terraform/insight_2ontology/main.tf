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
  image                    = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}/insight-2ontology:${var.image_tag}"
  whisper_completion_topic = "projects/${var.project_id}/topics/whisper-completion"
  ontology_completion_topic = "projects/${var.project_id}/topics/ontology-completion"
}

# ── Service account ───────────────────────────────────────────────────────────

resource "google_service_account" "insight_2ontology" {
  account_id   = "insight-2ontology-sa"
  display_name = "Insight2Ontology Service Account"
}

resource "google_project_iam_member" "ontology_gcs" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.insight_2ontology.email}"
}

resource "google_project_iam_member" "ontology_pubsub_publisher" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.insight_2ontology.email}"
}

resource "google_project_iam_member" "ontology_pubsub_subscriber" {
  project = var.project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.insight_2ontology.email}"
}

resource "google_project_iam_member" "ontology_vertexai_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.insight_2ontology.email}"
}

# ── Pub/Sub: ontology-completion topic ───────────────────────────────────────

resource "google_pubsub_topic" "ontology_completion" {
  name = "ontology-completion"
}

# ── Pub/Sub: whisper-completion push subscription ────────────────────────────

resource "google_cloud_run_v2_service_iam_member" "pubsub_invoker" {
  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.insight_2ontology.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.insight_2ontology.email}"
}

resource "google_pubsub_subscription" "whisper_completion_sub" {
  name  = "2ontology-whisper-completion-sub"
  topic = local.whisper_completion_topic

  ack_deadline_seconds = 300  # LLM calls can be slow

  push_config {
    push_endpoint = "${google_cloud_run_v2_service.insight_2ontology.uri}/pubsub/whisper-completion"

    oidc_token {
      service_account_email = google_service_account.insight_2ontology.email
    }
  }
}

# ── Cloud Run service ─────────────────────────────────────────────────────────

resource "google_cloud_run_v2_service" "insight_2ontology" {
  name     = "insight-2ontology"
  location = var.region

  template {
    service_account = google_service_account.insight_2ontology.email

    containers {
      image = local.image

      ports {
        container_port = 8080
      }

      env {
        name  = "ONTOLOGY_COMPLETION_TOPIC"
        value = local.ontology_completion_topic
      }

      env {
        name  = "GCP_PROJECT"
        value = var.project_id
      }

      env {
        name  = "AA_INGEST_TOPIC"
        value = "projects/${var.project_id}/topics/aa-ingest"
      }

      env {
        name  = "LLM_MODEL"
        value = var.llm_model
      }

      resources {
        limits = {
          cpu    = "2"
          memory = "2Gi"
        }
      }
    }

    # LLM calls can take 30-120s for long narratives
    timeout = "300s"
  }
}

# ── BigQuery table ────────────────────────────────────────────────────────────

resource "google_bigquery_table" "ontology_completion" {
  dataset_id          = "insight_metadata"
  table_id            = "ontology_completion"
  deletion_protection = false

  schema = jsonencode([
    { name = "video_id",    type = "STRING",    mode = "REQUIRED", description = "Unique identifier for the video" },
    { name = "status",      type = "STRING",    mode = "REQUIRED", description = "Processing status: completed or failed" },
    { name = "node_count",  type = "INTEGER",   mode = "NULLABLE", description = "Number of ontology nodes produced" },
    { name = "rel_count",   type = "INTEGER",   mode = "NULLABLE", description = "Number of ontology relationships produced" },
    { name = "output_path", type = "STRING",    mode = "NULLABLE", description = "GCS path to the ontology JSON file" },
    { name = "timestamp",   type = "TIMESTAMP", mode = "REQUIRED", description = "ISO 8601 timestamp of completion" },
  ])
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "insight_2ontology_url" {
  value = google_cloud_run_v2_service.insight_2ontology.uri
}
