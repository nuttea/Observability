# ============================================================
# variables.tf — Datadog NDM Containerlab Lab
# ============================================================

# ── GCP ─────────────────────────────────────────────────────
variable "gcp_project" {
  description = "GCP Project ID"
  type        = string
}

variable "gcp_region" {
  description = "GCE Region (must support N2 Intel with nested virt)"
  type        = string
  default     = "asia-southeast1"
}

variable "gcp_zone" {
  description = "GCE Zone"
  type        = string
  default     = "asia-southeast1-a"
}

variable "gce_service_account" {
  description = "Service account email for the GCE instance"
  type        = string
}

variable "machine_type" {
  description = "GCE machine type — must be N2 Intel for nested KVM"
  type        = string
  default     = "n2-standard-16"
}

variable "min_cpu_platform" {
  description = "Minimum CPU platform for nested virt support"
  type        = string
  default     = "Intel Cascade Lake"
}

variable "disk_size_gb" {
  description = "Boot disk size in GB (min 150 recommended for all VM images)"
  type        = number
  default     = 200
}

variable "ssh_public_key" {
  description = "SSH public key content for labuser (e.g. contents of ~/.ssh/id_ed25519.pub)"
  type        = string
}


variable "subnet_cidr" {
  description = "Subnet CIDR for the lab VPC"
  type        = string
  default     = "10.100.0.0/24"
}

variable "lab_name" {
  description = "Unique name prefix for all lab resources"
  type        = string
  default     = "ddlab-ndm"
}

# ── Image cache bucket ───────────────────────────────────────
# GCS bucket that persists the licensed CSR1000v qcow2 AND the
# pre-built vrnetlab Docker image tarball across `terraform destroy`
# cycles. Without this, every fresh apply requires re-uploading the
# ~1.4 GB qcow2 and rebuilding the image (~10 min).
#
# First-time setup flow:
#   1. terraform apply                  → creates bucket + VM
#   2. gsutil cp <csr.qcow2> gs://<bucket>/csr1000v.qcow2   (once)
#   3. gcloud compute instances reset <lab_name>
#   4. Wait ~15 min — startup script builds the image, caches it
#      back to the bucket, and deploys the lab automatically.
#
# On subsequent `terraform destroy && terraform apply`, the cache
# hit in step (1) skips the qcow2 step entirely; deploy in ~10 min.
variable "image_cache_bucket_name" {
  description = "GCS bucket name for CSR1000v qcow2 + built image cache. If empty, defaults to <project>-<lab_name>-cache."
  type        = string
  default     = ""
}

variable "image_cache_force_destroy" {
  description = "If true, terraform destroy will also delete cached objects in the image bucket. Keep false to preserve the cache across destroys (the common case)."
  type        = bool
  default     = false
}

variable "team_label" {
  description = "GCP label value for the 'team' key"
  type        = string
  default     = "se-labs"
}

# ── Datadog ──────────────────────────────────────────────────
# dd_api_key has no default — Terraform will prompt interactively if not set
# in terraform.tfvars or via TF_VAR_dd_api_key / -var="dd_api_key=..."
variable "dd_api_key" {
  description = "Datadog API Key (from https://app.datadoghq.com/organization-settings/api-keys)"
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.dd_api_key) > 0
    error_message = "dd_api_key must not be empty. Get one from https://app.<dd_site>/organization-settings/api-keys."
  }
}

# dd_site has no default — Terraform will prompt interactively if not set.
# Allowed values: datadoghq.com, us3.datadoghq.com, us5.datadoghq.com
variable "dd_site" {
  description = "Datadog site. Allowed: datadoghq.com (US1), us3.datadoghq.com (US3), us5.datadoghq.com (US5)"
  type        = string

  validation {
    condition     = contains(["datadoghq.com", "us3.datadoghq.com", "us5.datadoghq.com"], var.dd_site)
    error_message = "dd_site must be one of: datadoghq.com, us3.datadoghq.com, us5.datadoghq.com."
  }
}

variable "dd_namespace" {
  description = "NDM namespace to group all lab devices"
  type        = string
  default     = "lab-th"
}

# ── Lab Network ──────────────────────────────────────────────
variable "lab_mgmt_subnet" {
  description = "Management subnet for Containerlab nodes (Docker bridge)"
  type        = string
  default     = "172.20.20.0/24"
}

variable "csr_mgmt_ip" {
  description = "Cisco CSR1 management IP (Bangkok DC1 Edge)"
  type        = string
  default     = "172.20.20.10"
}

variable "csr2_mgmt_ip" {
  description = "Cisco CSR2 management IP (WAN Transit)"
  type        = string
  default     = "172.20.20.11"
}

variable "csr3_mgmt_ip" {
  description = "Cisco CSR3 management IP (Chiang Mai DC2 Edge)"
  type        = string
  default     = "172.20.20.12"
}

variable "csr4_mgmt_ip" {
  description = "Cisco CSR4 management IP (Chiang Mai DC2 Access — 4th hop)"
  type        = string
  default     = "172.20.20.14"
}

variable "csr5_mgmt_ip" {
  description = "Cisco CSR5 management IP (Chiang Mai DC2 Endpoint — 5th hop)"
  type        = string
  default     = "172.20.20.15"
}

# ── Deprecated (kept to avoid breaking existing tfvars) ──
# PAN and F5 removed from topology — variables retained only so older
# terraform.tfvars files keep working. Not referenced by the lab.
variable "pan_mgmt_ip" {
  description = "[DEPRECATED — unused] Palo Alto PA-VM management IP"
  type        = string
  default     = "172.20.20.20"
}

variable "f5_active_mgmt_ip" {
  description = "[DEPRECATED — unused] F5 BIG-IP Active management IP"
  type        = string
  default     = "172.20.20.31"
}

variable "f5_standby_mgmt_ip" {
  description = "[DEPRECATED — unused] F5 BIG-IP Standby management IP"
  type        = string
  default     = "172.20.20.32"
}

variable "agent_mgmt_ip" {
  description = "Datadog Agent management IP"
  type        = string
  default     = "172.20.20.5"
}

# ── SNMP Credentials ─────────────────────────────────────────
variable "snmp_community" {
  description = "SNMPv2c community string (used for read-only polling)"
  type        = string
  default     = "dd-snmp-ro"
  sensitive   = true
}

variable "snmp_v3_user" {
  description = "SNMPv3 username"
  type        = string
  default     = "dduser"
}

variable "snmp_v3_auth_pass" {
  description = "SNMPv3 authentication password (SHA, min 8 chars)"
  type        = string
  sensitive   = true
}

variable "snmp_v3_priv_pass" {
  description = "SNMPv3 privacy password (AES128, min 8 chars)"
  type        = string
  sensitive   = true
}

variable "device_password" {
  description = "Common management password for lab devices (CSR, F5, PAN)"
  type        = string
  sensitive   = true
}

# ── BGP ──────────────────────────────────────────────────────
variable "bgp_local_as" {
  description = "BGP AS number for the Cisco CSR"
  type        = number
  default     = 65000
}

variable "bgp_peer_as" {
  description = "BGP AS number for the FRR peer (internet simulation)"
  type        = number
  default     = 65001
}

# ── VM Image Tags ────────────────────────────────────────────
variable "csr_image_tag" {
  description = "Docker image tag for the built Cisco CSR1000v vrnetlab image (e.g. vrnetlab/cisco_csr1000v:16.07.01)"
  type        = string
  # No default — image is user-built from a licensed qcow2; version varies
}

variable "pan_image_tag" {
  description = "Docker image tag for the built PAN-OS vrnetlab image (e.g. vrnetlab/paloalto_pa-vm:11.0.0)"
  type        = string
  # No default — image is user-built from a licensed qcow2; version varies
}

variable "f5_image_tag" {
  description = "Docker image tag for the built F5 BIG-IP VE vrnetlab image (e.g. vrnetlab/f5_bigip-ve:16.1.6.1-0.0.11)"
  type        = string
  # No default — image is user-built from a licensed qcow2; version varies
}

variable "f5_license_key" {
  description = "F5 BIG-IP VE registration key for LTM licensing. If empty, LTM features (VIP/pool) are skipped and an nginx reverse proxy is deployed instead."
  type        = string
  default     = ""
  sensitive   = true
}

# ── Geomap — Thailand Locations ──────────────────────────────
variable "geo_bkk_lat" {
  description = "Latitude for Bangkok (Datadog Geomap)"
  type        = string
  default     = "13.7563"
}

variable "geo_bkk_lon" {
  description = "Longitude for Bangkok (Datadog Geomap)"
  type        = string
  default     = "100.5018"
}

variable "geo_bkk_label" {
  description = "Display label for Bangkok location in Geomap"
  type        = string
  default     = "Bangkok-DC1"
}

variable "geo_cnx_lat" {
  description = "Latitude for Chiang Mai (Datadog Geomap)"
  type        = string
  default     = "18.7883"
}

variable "geo_cnx_lon" {
  description = "Longitude for Chiang Mai (Datadog Geomap)"
  type        = string
  default     = "98.9853"
}

variable "geo_cnx_label" {
  description = "Display label for Chiang Mai location in Geomap"
  type        = string
  default     = "ChiangMai-DC2"
}
