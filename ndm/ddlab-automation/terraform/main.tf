# ============================================================
# Datadog NDM + Network Path Containerlab — GCE Lab Host
# Terraform v1.5+  |  Provider: google ~> 5.0
# ============================================================
# Provisions:
#   - VPC + Subnet (Private Google Access enabled)
#   - Cloud Router + Cloud NAT (internet egress, no public IP)
#   - Firewall: IAP SSH (35.235.240.0/20), internal, HTTPS egress
#   - n2-standard-8 GCE instance (Intel, nested KVM, no public IP)
#   - Startup script that installs all tooling and renders
#     all Datadog / Containerlab config files from tfvars
# ============================================================

terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }
  required_version = ">= 1.5"
}

provider "google" {
  project = var.gcp_project
  region  = var.gcp_region
  zone    = var.gcp_zone
}

# ── Locals ──────────────────────────────────────────────────
locals {
  labels = {
    env     = "lab"
    purpose = "datadog-ndm-containerlab"
    team    = var.team_label
  }

  # Google IAP TCP forwarding proxy CIDR — only source for IAP-tunnelled SSH
  # Ref: https://cloud.google.com/iap/docs/using-tcp-forwarding#create-firewall-rule
  google_iap_cidr = "35.235.240.0/20"

  # Default cache bucket name ("<project>-<lab>-cache") if user doesn't
  # override. Project-scoped — avoids global GCS namespace collisions.
  image_cache_bucket = coalesce(
    var.image_cache_bucket_name,
    "${var.gcp_project}-${var.lab_name}-cache"
  )

  startup_script = templatefile("${path.module}/../scripts/startup.sh.tpl", {
    image_cache_bucket = local.image_cache_bucket
    dd_api_key         = var.dd_api_key
    dd_site            = var.dd_site
    dd_namespace       = var.dd_namespace
    lab_name           = var.lab_name
    lab_mgmt_subnet    = var.lab_mgmt_subnet
    snmp_community     = var.snmp_community
    snmp_v3_user       = var.snmp_v3_user
    snmp_v3_auth_pass  = var.snmp_v3_auth_pass
    snmp_v3_priv_pass  = var.snmp_v3_priv_pass
    device_password    = var.device_password
    csr_mgmt_ip        = var.csr_mgmt_ip
    csr2_mgmt_ip       = var.csr2_mgmt_ip
    csr3_mgmt_ip       = var.csr3_mgmt_ip
    csr4_mgmt_ip       = var.csr4_mgmt_ip
    csr5_mgmt_ip       = var.csr5_mgmt_ip
    pan_mgmt_ip        = var.pan_mgmt_ip
    f5_active_mgmt_ip  = var.f5_active_mgmt_ip
    f5_standby_mgmt_ip = var.f5_standby_mgmt_ip
    agent_mgmt_ip      = var.agent_mgmt_ip
    geo_bkk_lat        = var.geo_bkk_lat
    geo_bkk_lon        = var.geo_bkk_lon
    geo_cnx_lat        = var.geo_cnx_lat
    geo_cnx_lon        = var.geo_cnx_lon
    geo_bkk_label      = var.geo_bkk_label
    geo_cnx_label      = var.geo_cnx_label
    bgp_local_as       = var.bgp_local_as
    bgp_peer_as        = var.bgp_peer_as
    csr_image_tag      = var.csr_image_tag
    pan_image_tag      = var.pan_image_tag
    f5_image_tag       = var.f5_image_tag
    f5_license_key     = var.f5_license_key
  })
}

# ── Image cache bucket ───────────────────────────────────────
# Persists the licensed CSR1000v qcow2 + the pre-built vrnetlab
# Docker image tarball. On `terraform apply`, the GCE startup script
# checks this bucket and either:
#   - loads a cached docker-image tarball (fast, seconds)
#   - builds from the cached qcow2 and re-uploads the tarball (slow, once)
#   - logs upload instructions if neither is present (first-time setup)
resource "google_storage_bucket" "image_cache" {
  name                        = local.image_cache_bucket
  location                    = var.gcp_region
  force_destroy               = var.image_cache_force_destroy
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  labels                      = local.labels

  lifecycle {
    # Never replace the bucket silently. If you really want to start
    # over, set image_cache_force_destroy=true and run terraform
    # destroy, or run `terraform state rm` to detach from state and
    # delete manually via gsutil.
    prevent_destroy = false
  }
}

# Grant the GCE VM's service account read/write access to the cache.
resource "google_storage_bucket_iam_member" "image_cache_sa" {
  bucket = google_storage_bucket.image_cache.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${var.gce_service_account}"
}

# ── VPC ─────────────────────────────────────────────────────
resource "google_compute_network" "lab_vpc" {
  name                    = "${var.lab_name}-vpc"
  auto_create_subnetworks = false
  description             = "Datadog NDM Containerlab Lab VPC"
}

resource "google_compute_subnetwork" "lab_subnet" {
  name          = "${var.lab_name}-subnet"
  ip_cidr_range = var.subnet_cidr
  network       = google_compute_network.lab_vpc.id
  region        = var.gcp_region

  # Required for Private Google Access (APIs, GCS, etc.) when no public IP
  private_ip_google_access = true
}

# ── Cloud Router + NAT (internet egress without public IP) ──
resource "google_compute_router" "lab_router" {
  name        = "${var.lab_name}-router"
  network     = google_compute_network.lab_vpc.id
  region      = var.gcp_region
  description = "Cloud Router for NAT egress"
}

resource "google_compute_router_nat" "lab_nat" {
  name                               = "${var.lab_name}-nat"
  router                             = google_compute_router.lab_router.name
  region                             = var.gcp_region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "ALL_SUBNETWORKS_ALL_IP_RANGES"

  log_config {
    enable = true
    filter = "ERRORS_ONLY"
  }
}

# ── Firewall ─────────────────────────────────────────────────

# IAP SSH — only Google's IAP proxy can initiate TCP:22 connections here
resource "google_compute_firewall" "allow_iap_ssh" {
  name        = "${var.lab_name}-allow-iap-ssh"
  network     = google_compute_network.lab_vpc.name
  description = "Allow SSH only via Google IAP tunnel (${local.google_iap_cidr})"

  allow {
    protocol = "tcp"
    ports    = ["22"]
  }

  source_ranges = [local.google_iap_cidr]
  target_tags   = [var.lab_name]
}

# Allow all traffic within the subnet (Containerlab bridge networks)
resource "google_compute_firewall" "allow_internal" {
  name        = "${var.lab_name}-allow-internal"
  network     = google_compute_network.lab_vpc.name
  description = "Allow all internal lab traffic within the subnet"

  allow {
    protocol = "all"
  }

  source_ranges = [var.subnet_cidr]
  target_tags   = [var.lab_name]
}

# Egress HTTPS — Datadog ingest, Docker Hub, GCS, apt repos (via Cloud NAT)
resource "google_compute_firewall" "allow_egress_https" {
  name        = "${var.lab_name}-allow-egress-https"
  network     = google_compute_network.lab_vpc.name
  direction   = "EGRESS"
  description = "Allow HTTPS egress for Datadog, Docker Hub, GCS via Cloud NAT"

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = [var.lab_name]
}

# Egress HTTP — apt/yum package repos, vrnetlab image registries
resource "google_compute_firewall" "allow_egress_http" {
  name        = "${var.lab_name}-allow-egress-http"
  network     = google_compute_network.lab_vpc.name
  direction   = "EGRESS"
  description = "Allow HTTP egress for package repositories via Cloud NAT"

  allow {
    protocol = "tcp"
    ports    = ["80"]
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = [var.lab_name]
}

# ── GCE Instance (no public IP — accessed via IAP tunnel) ────
resource "google_compute_instance" "lab_host" {
  name         = var.lab_name
  machine_type = var.machine_type
  zone         = var.gcp_zone
  tags         = [var.lab_name]
  labels       = local.labels

  # N2 Intel with nested virtualization (required for QEMU/KVM vrnetlab VMs)
  advanced_machine_features {
    enable_nested_virtualization = true
    threads_per_core             = 2
  }

  # Intel Cascade Lake guarantees KVM support on GCE
  min_cpu_platform = var.min_cpu_platform

  boot_disk {
    # Keep disk on instance destroy — vrnetlab images take ~30min to rebuild
    auto_delete = false

    initialize_params {
      image = "debian-cloud/debian-12"
      size  = var.disk_size_gb
      type  = "pd-ssd"
    }
  }

  network_interface {
    subnetwork = google_compute_subnetwork.lab_subnet.id
    # No access_config block = no public IP; internet via Cloud NAT
  }

  service_account {
    email  = var.gce_service_account
    scopes = ["cloud-platform"]
  }

  metadata = {
    ssh-keys               = "labuser:${var.ssh_public_key}"
    enable-oslogin         = "false"
    block-project-ssh-keys = "true"
    startup-script         = local.startup_script
  }

  deletion_protection       = false
  allow_stopping_for_update = true

  # Ensure the cache bucket + IAM are ready before the VM boots and
  # the startup script tries to `gsutil ls`.
  depends_on = [
    google_storage_bucket_iam_member.image_cache_sa,
  ]
}
