variable "project_id"    { type = string }
variable "region"        { type = string }
variable "artifact_repo" { type = string }

variable "image_tag" {
  type    = string
  default = "latest"
}

variable "llm_model" {
  type    = string
  default = "gemini-2.5-flash"
}
