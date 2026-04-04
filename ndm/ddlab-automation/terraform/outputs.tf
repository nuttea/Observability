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

output "datadog_ndm_url" {
  description = "Direct link to NDM in Datadog"
  value       = "https://app.${var.dd_site}/devices"
}

output "geomap_locations" {
  description = "NDM Geomap location summary for Thailand sites"
  value = {
    bangkok = {
      label     = var.geo_bkk_label
      latitude  = var.geo_bkk_lat
      longitude = var.geo_bkk_lon
      devices   = ["csr-router", "pan-firewall"]
    }
    chiang_mai = {
      label     = var.geo_cnx_label
      latitude  = var.geo_cnx_lat
      longitude = var.geo_cnx_lon
      devices   = ["f5-bigip-active", "f5-bigip-standby"]
    }
  }
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
