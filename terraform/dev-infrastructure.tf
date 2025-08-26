# Dev MongoDB VM (Vulnerable)
resource "google_compute_instance" "dev_mongodb" {
  name         = "dev-mongodb-vm"
  machine_type = "e2-medium"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud-devel/ubuntu-1604-lts"  # Outdated OS
      size  = 20
    }
  }

  network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.dev_subnet.name
    
    access_config {
      // Public IP
    }
  }

  metadata = {
    gcs-bucket = "${var.project_id}-dev-mongodb-backups"
  }

  metadata_startup_script = file("${path.module}/../scripts/install-mongodb-vulnerable.sh")

  tags = ["dev-mongodb", "allow-all-ssh", "allow-mongodb-public"]

  labels = {
    environment = "dev"
    vulnerable  = "true"
  }
}

# Dev firewall rules
resource "google_compute_firewall" "dev_allow_ssh_all" {
  name    = "dev-allow-ssh-from-anywhere"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-all-ssh"]
}

resource "google_compute_firewall" "dev_allow_mongodb_public" {
  name    = "dev-allow-mongodb-public"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["27017", "8081", "28017"]
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["allow-mongodb-public"]
}

# Dev GKE Cluster (Intentionally overly permissive)
resource "google_container_cluster" "dev_cluster" {
  name               = "dev-gke-cluster"
  location           = var.zone
  initial_node_count = 2

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.dev_subnet.name

  ip_allocation_policy {
    cluster_secondary_range_name  = "dev-pods"
    services_secondary_range_name = "dev-services"
  }

  # Disable managed prometheus to avoid webhook issues (intentionally insecure)
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS"]
    managed_prometheus {
      enabled = false
    }
  }

  node_config {
    machine_type = "e2-standard-2"
    
    # VULNERABILITY: Overly broad OAuth scopes
    oauth_scopes = [
      "https://www.googleapis.com/auth/cloud-platform"
    ]

    labels = {
      environment = "dev"
      vulnerable  = "true"
    }

    tags = ["dev-gke-node"]
  }
}

# GitHub Actions Service Account for CI/CD (needed for Terraform backend access)
resource "google_service_account" "github_actions_sa" {
  account_id   = "github-actions-sa"
  display_name = "GitHub Actions Service Account"
  description  = "Service account for GitHub Actions CI/CD pipeline with Terraform permissions"
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


# Dev GCS Bucket (Public)
resource "google_storage_bucket" "dev_mongodb_backups" {
  name          = "${var.project_id}-dev-mongodb-backups"
  location      = var.region
  force_destroy = true
}

resource "google_storage_bucket_iam_member" "dev_public_read" {
  bucket = google_storage_bucket.dev_mongodb_backups.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}
