terraform {
  required_providers {
    google          = { source = "hashicorp/google",          version = "~> 5.0" }
    google-beta     = { source = "hashicorp/google-beta",     version = "~> 5.0" }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
}

# Enable Firebase on the project
resource "google_firebase_project" "insightcircle" {
  provider = google-beta
  project  = var.project_id
}

# Firebase Hosting site for the Flutter web build
resource "google_firebase_hosting_site" "insight_visual" {
  provider = google-beta
  project  = var.project_id
  site_id  = "insight-visual"

  depends_on = [google_firebase_project.insightcircle]
}

output "hosting_url" {
  value = "https://${google_firebase_hosting_site.insight_visual.site_id}.web.app"
}
