variable "project_id" {
  description = "GCP Project ID"
  type        = string
  default     = "clgcporg10-173"
}

variable "region" {
  description = "GCP Region"
  type        = string
  default     = "us-central1"
}

variable "zone" {
  description = "GCP Zone"
  type        = string
  default     = "us-central1-c"
}

variable "disk_encryption_key" {
  description = "Disk encryption key for production"
  type        = string
  sensitive   = true
  default     = ""
}
