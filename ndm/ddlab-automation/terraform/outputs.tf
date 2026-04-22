# outputs.tf

output "instance_name" {
  description = "GCE instance name"
  value       = google_compute_instance.lab_host.name
}

output "instance_zone" {
  description = "GCE instance zone"
  value       = var.gcp_zone
}

output "ssh_command" {
  description = "SSH command via IAP tunnel (no public IP required)"
  value       = "gcloud compute ssh labuser@${var.lab_name} --zone=${var.gcp_zone} --project=${var.gcp_project} --tunnel-through-iap"
}

output "kvm_verify_command" {
  description = "Verify KVM is available via IAP tunnel"
  value       = "gcloud compute ssh labuser@${var.lab_name} --zone=${var.gcp_zone} --project=${var.gcp_project} --tunnel-through-iap -- 'ls -la /dev/kvm && kvm-ok'"
}

output "lab_status_command" {
  description = "Check lab deployment status via IAP tunnel"
  value       = "gcloud compute ssh labuser@${var.lab_name} --zone=${var.gcp_zone} --project=${var.gcp_project} --tunnel-through-iap -- 'cat /var/log/ddlab-startup.log | tail -40'"
}

output "containerlab_inspect_command" {
  description = "Inspect running Containerlab topology via IAP tunnel"
  value       = "gcloud compute ssh labuser@${var.lab_name} --zone=${var.gcp_zone} --project=${var.gcp_project} --tunnel-through-iap -- 'sudo containerlab inspect --topo /opt/ddlab/containerlab/ndm-lab.clab.yml'"
}

output "agent_status_command" {
  description = "Check Datadog Agent status via IAP tunnel"
  value       = "gcloud compute ssh labuser@${var.lab_name} --zone=${var.gcp_zone} --project=${var.gcp_project} --tunnel-through-iap -- 'sudo datadog-agent status'"
}

output "startup_log_tail" {
  description = "Follow bootstrap log in real time via IAP tunnel"
  value       = "gcloud compute ssh labuser@${var.lab_name} --zone=${var.gcp_zone} --project=${var.gcp_project} --tunnel-through-iap -- 'tail -f /var/log/ddlab-startup.log'"
}

output "nat_gateway" {
  description = "Cloud NAT name providing outbound internet access"
  value       = google_compute_router_nat.lab_nat.name
}

locals {
  # US1 uses https://app.datadoghq.com; US3/US5 use https://<site>/ (no "app." prefix)
  dd_app_url = var.dd_site == "datadoghq.com" ? "https://app.datadoghq.com" : "https://${var.dd_site}"
}

output "datadog_ndm_url" {
  description = "Direct link to NDM in Datadog"
  value       = "${local.dd_app_url}/devices"
}

output "datadog_network_path_url" {
  description = "Direct link to Network Path in Datadog"
  value       = "${local.dd_app_url}/network/path"
}

output "datadog_app_url" {
  description = "Base Datadog app URL for this site"
  value       = local.dd_app_url
}

output "geomap_locations" {
  description = "NDM Geomap location summary for Thailand sites"
  value = {
    bangkok = {
      label     = var.geo_bkk_label
      latitude  = var.geo_bkk_lat
      longitude = var.geo_bkk_lon
      devices   = ["csr (CSR-BKK-EDGE, hop 1)"]
    }
    wan_transit = {
      label     = "WAN Transit"
      latitude  = "15.8700"
      longitude = "100.9925"
      devices   = ["csr2 (CSR-WAN-TRANSIT, hop 2)"]
    }
    chiang_mai = {
      label     = var.geo_cnx_label
      latitude  = var.geo_cnx_lat
      longitude = var.geo_cnx_lon
      devices   = ["csr3 (CSR-CNX-DC-EDGE, hop 3)"]
    }
  }
}

# ── Image cache — tells the user how to feed the lab its qcow2 ──────────────

output "image_cache_bucket" {
  description = "GCS bucket caching the CSR1000v qcow2 + built vrnetlab image"
  value       = google_storage_bucket.image_cache.name
}

output "cold_start_upload_command" {
  description = "First-time setup: upload the licensed CSR1000v qcow2 to the cache bucket, then reset the VM"
  value = <<-EOT
    # ──────────────────────────────────────────────────────────────────
    # ONE-TIME: upload your licensed CSR1000v qcow2 to the cache bucket
    # ──────────────────────────────────────────────────────────────────
    gsutil cp <path-to-csr1000v-universalk9.qcow2> \
      gs://${google_storage_bucket.image_cache.name}/csr1000v.qcow2

    # Then reset the VM so the startup script picks it up and
    # auto-deploys the lab (~15 min):
    gcloud compute instances reset ${var.lab_name} \
      --zone=${var.gcp_zone} \
      --project=${var.gcp_project}

    # Monitor progress:
    gcloud compute ssh labuser@${var.lab_name} \
      --zone=${var.gcp_zone} \
      --project=${var.gcp_project} \
      --tunnel-through-iap \
      --command='sudo tail -f /var/log/ddlab-deploy.log'
  EOT
}

# ── Sensitive outputs — not shown in terraform output by default ──────────────

output "dd_namespace" {
  description = "Datadog NDM namespace used for all lab devices"
  value       = var.dd_namespace
  sensitive   = false # not secret, safe to print
}

output "startup_script_rendered" {
  description = "Rendered startup script (contains secrets — handle with care)"
  value       = local.startup_script
  sensitive   = true
}
