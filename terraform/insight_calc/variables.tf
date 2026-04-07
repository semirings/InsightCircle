variable "project_id" { type = string }
variable "region"     { type = string }
variable "zone"       { type = string }
variable "bucket"     { type = string }
variable "pubsub_subscription" { type = string }
variable "artifact_repo"       { type = string }

variable "machine_type" {
  type    = string
  default = "e2-standard-2"
}
