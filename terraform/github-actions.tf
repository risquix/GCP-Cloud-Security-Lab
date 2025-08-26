# GitHub Actions Service Account for CI/CD
resource "google_service_account" "github_actions_sa" {
  account_id   = "github-actions-sa"
  display_name = "GitHub Actions Service Account"
  description  = "Service account for GitHub Actions CI/CD pipeline with Terraform permissions"
  
  lifecycle {
    ignore_changes = [
      # Ignore changes to these fields if they're managed outside Terraform
      display_name,
      description
    ]
  }
}

# GitHub Actions IAM binding for Terraform state bucket
resource "google_storage_bucket_iam_member" "github_actions_terraform_state" {
  bucket = "clgcporg10-173-terraform-state"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

# GitHub Actions IAM binding for general project permissions
resource "google_project_iam_member" "github_actions_editor" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.github_actions_sa.email}"
}

# GitHub Actions IAM binding for Security Command Center
resource "google_project_iam_member" "github_actions_security_center" {
  project = var.project_id
  role    = "roles/securitycenter.admin"
  member  = "serviceAccount:${google_service_account.github_actions_sa.email}"
}