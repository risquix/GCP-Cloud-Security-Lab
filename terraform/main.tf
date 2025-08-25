terraform {
  required_version = ">= 1.5.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
    google-beta = {
      source  = "hashicorp/google-beta"
      version = "~> 5.0"
    }
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

provider "google-beta" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

# Data source for project
data "google_project" "project" {
  project_id = var.project_id
}

# Shared VPC Network
resource "google_compute_network" "vpc" {
  name                    = "wiz-lab-vpc"
  auto_create_subnetworks = false
}

# Dev Subnet
resource "google_compute_subnetwork" "dev_subnet" {
  name          = "dev-subnet"
  ip_cidr_range = "10.0.1.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  
  secondary_ip_range {
    range_name    = "dev-pods"
    ip_cidr_range = "10.1.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "dev-services"
    ip_cidr_range = "10.2.0.0/16"
  }
}

# Prod Subnet  
resource "google_compute_subnetwork" "prod_subnet" {
  name          = "prod-subnet"
  ip_cidr_range = "10.0.2.0/24"
  region        = var.region
  network       = google_compute_network.vpc.id
  
  secondary_ip_range {
    range_name    = "prod-pods"
    ip_cidr_range = "10.3.0.0/16"
  }
  
  secondary_ip_range {
    range_name    = "prod-services"
    ip_cidr_range = "10.4.0.0/16"
  }

  private_ip_google_access = true
}
