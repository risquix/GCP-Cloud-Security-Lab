output "dev_mongodb_public_ip" {
  value = google_compute_instance.dev_mongodb.network_interface[0].access_config[0].nat_ip
  description = "Public IP of dev MongoDB VM (VULNERABLE)"
}

output "dev_public_backup_url" {
  value = "https://storage.googleapis.com/${google_storage_bucket.dev_mongodb_backups.name}/"
  description = "Public URL for dev MongoDB backups (VULNERABLE)"
}

output "dev_gke_cluster_name" {
  value = google_container_cluster.dev_cluster.name
  description = "Dev GKE cluster name"
}

output "prod_gke_cluster_name" {
  value = google_container_cluster.prod_cluster.name
  description = "Prod GKE cluster name"
}
