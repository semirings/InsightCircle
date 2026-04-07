terraform {
  required_providers {
    google = { source = "hashicorp/google", version = "~> 5.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# Staging bucket for the function source zip
resource "google_storage_bucket" "ingest_source" {
  name          = "${var.project_id}-ingest-source"
  location      = "US"
  force_destroy = true
}

resource "google_storage_bucket_object" "ingest_source_zip" {
  name   = "ingest.zip"
  bucket = google_storage_bucket.ingest_source.name
  source = "${path.module}/../../ingest.zip"   # built by tfc.sh before apply
}

resource "google_service_account" "ingest" {
  account_id   = "ingest-sa"
  display_name = "Ingest FaaS Service Account"
}

resource "google_project_iam_member" "ingest_gcs" {
  project = var.project_id
  role    = "roles/storage.objectAdmin"
  member  = "serviceAccount:${google_service_account.ingest.email}"
}

resource "google_cloudfunctions2_function" "ingest" {
  name     = "ingest"
  location = var.region

  build_config {
    runtime     = "python311"
    entry_point = "main"

    source {
      storage_source {
        bucket = google_storage_bucket.ingest_source.name
        object = google_storage_bucket_object.ingest_source_zip.name
      }
    }
  }

  service_config {
    service_account_email = google_service_account.ingest.email
    available_memory      = "512M"
    timeout_seconds       = 540

    environment_variables = {
      YOUTUBE_API_KEY = var.youtube_api_key
    }
  }
}

output "ingest_function_url" {
  value = google_cloudfunctions2_function.ingest.service_config[0].uri
}
