variable "project_id"    { type = string }
variable "region"        { type = string }
variable "artifact_repo" { type = string }

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "bq_dataset" {
  type    = string
  default = "insight_metadata"
}
