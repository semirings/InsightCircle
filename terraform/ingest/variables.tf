variable "project_id"          { type = string }
variable "region"              { type = string }
variable "zone"                { type = string }
variable "bucket"              { type = string }
variable "artifact_repo"       { type = string }
variable "pubsub_subscription" { type = string }

variable "youtube_api_key" {
  type      = string
  sensitive = true
  default   = ""
}
