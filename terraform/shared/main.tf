terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ── Artifact Registry ─────────────────────────────────────────────────────────

resource "google_artifact_registry_repository" "insightcircle" {
  repository_id = var.artifact_repo
  location      = var.region
  format        = "DOCKER"
  description   = "InsightCircle container images"
}

# ── GCS bucket ────────────────────────────────────────────────────────────────

resource "google_storage_bucket" "insightcircle" {
  name          = var.bucket
  location      = "US"
  force_destroy = false

  uniform_bucket_level_access = true
}

# ── PubSub topic & subscription ───────────────────────────────────────────────

resource "google_pubsub_topic" "aa_ingest" {
  name = "aa-ingest"
}

resource "google_pubsub_subscription" "aa_ingest_sub" {
  name  = var.pubsub_subscription
  topic = google_pubsub_topic.aa_ingest.name

  ack_deadline_seconds = 60
}

# ── Outputs (consumed as vars by service modules) ─────────────────────────────

output "artifact_registry_host" {
  value = "${var.region}-docker.pkg.dev"
}

output "image_prefix" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/${var.artifact_repo}"
}
