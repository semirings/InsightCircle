variable "project_id"    { type = string }
variable "region"        { type = string }
variable "zone"          { type = string }
variable "bucket"        { type = string }
variable "artifact_repo" { type = string }
variable "pubsub_subscription" { type = string }

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "whisper_model" {
  type    = string
  default = "base"
}
