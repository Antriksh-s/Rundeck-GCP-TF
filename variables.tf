variable "gcp_project_id" {
  type        = string
  description = "The GCP Project ID to deploy Rundeck into."
}

variable "gcp_region" {
  type        = string
  default     = "us-central1"
  description = "GCP Region."
}

variable "gcp_zone" {
  type        = string
  default     = "us-central1-a"
  description = "GCP Zone."
}

variable "machine_type" {
  type        = string
  default     = "e2-medium"
  description = "GCP Instance Machine Type."
}