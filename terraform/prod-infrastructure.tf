# Prod MongoDB VM (Secure)
resource "google_compute_instance" "prod_mongodb" {
  name         = "prod-mongodb-vm"
  machine_type = "e2-standard-2"
  zone         = var.zone

  boot_disk {
    initialize_params {
      image = "ubuntu-os-cloud/ubuntu-2204-lts"
      size  = 50
      type  = "pd-ssd"
    }
  }

  network_interface {
    network    = google_compute_network.vpc.name
    subnetwork = google_compute_subnetwork.prod_subnet.name
    # No public IP
  }

  metadata = {
    gcs-bucket = "${var.project_id}-prod-mongodb-backups"
  }

  metadata_startup_script = file("${path.module}/../scripts/install-mongodb-secure.sh")

  tags = ["prod-mongodb", "allow-iap-ssh"]

  labels = {
    environment = "prod"
    compliance  = "pci-dss"
  }

  shielded_instance_config {
    enable_secure_boot          = true
    enable_vtpm                 = true
    enable_integrity_monitoring = true
  }
}

# Prod firewall rules
resource "google_compute_firewall" "prod_allow_iap_ssh" {
  name    = "prod-allow-iap-ssh"
  network = google_compute_network.vpc.name

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = ["35.235.240.0/20"]  # IAP range
  target_tags   = ["allow-iap-ssh"]
}

# Prod GKE Service Account
resource "google_service_account" "prod_gke_sa" {
  account_id   = "prod-gke-sa"
  display_name = "Prod GKE Service Account"
  description  = "Service account for prod GKE cluster with minimal required permissions"
}

# Prod GKE IAM bindings - minimal required permissions
resource "google_project_iam_member" "prod_gke_node_service_account" {
  project = var.project_id
  role    = "roles/container.defaultNodeServiceAccount"
  member  = "serviceAccount:${google_service_account.prod_gke_sa.email}"
}

resource "google_project_iam_member" "prod_gke_logging" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.prod_gke_sa.email}"
}

resource "google_project_iam_member" "prod_gke_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.prod_gke_sa.email}"
}

resource "google_project_iam_member" "prod_gke_monitoring_viewer" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.prod_gke_sa.email}"
}

resource "google_project_iam_member" "prod_gke_gcr" {
  project = var.project_id
  role    = "roles/storage.objectViewer"
  member  = "serviceAccount:${google_service_account.prod_gke_sa.email}"
}

resource "google_project_iam_member" "prod_gke_artifact_registry" {
  project = var.project_id
  role    = "roles/artifactregistry.reader"
  member  = "serviceAccount:${google_service_account.prod_gke_sa.email}"
}

# Prod GKE Cluster
resource "google_container_cluster" "prod_cluster" {
  name     = "prod-gke-cluster"
  location = var.region
  
  remove_default_node_pool = true
  initial_node_count       = 1

  network    = google_compute_network.vpc.name
  subnetwork = google_compute_subnetwork.prod_subnet.name

  enable_shielded_nodes = true

  private_cluster_config {
    enable_private_nodes    = true
    enable_private_endpoint = false
    master_ipv4_cidr_block = "172.16.0.0/28"
  }

  ip_allocation_policy {
    cluster_secondary_range_name  = "prod-pods"
    services_secondary_range_name = "prod-services"
  }

  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }

  # Enable managed prometheus with proper configuration
  monitoring_config {
    enable_components = ["SYSTEM_COMPONENTS", "WORKLOADS"]
    managed_prometheus {
      enabled = true
    }
  }
}

resource "google_container_node_pool" "prod_nodes" {
  name       = "prod-node-pool"
  location   = var.region
  cluster    = google_container_cluster.prod_cluster.name
  node_count = 3

  node_config {
    machine_type    = "e2-standard-4"
    service_account = google_service_account.prod_gke_sa.email
    
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
      "https://www.googleapis.com/auth/devstorage.read_only"
    ]

    labels = {
      environment = "prod"
    }

    tags = ["prod-gke-node"]

    shielded_instance_config {
      enable_secure_boot = true
    }
  }
}


# Prod GCS Bucket (Private)
resource "google_storage_bucket" "prod_mongodb_backups" {
  name          = "${var.project_id}-prod-mongodb-backups"
  location      = var.region
  force_destroy = false

  uniform_bucket_level_access = true

  versioning {
    enabled = true
  }
}
