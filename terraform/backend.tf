terraform {
  backend "gcs" {
    bucket = "clgcporg10-173-terraform-state"
    prefix = "terraform/state"
  }
}
