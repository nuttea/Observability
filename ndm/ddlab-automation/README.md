# Datadog NDM + NetworkPath — Containerlab Lab Automation

Terraform + bootstrap scripts that spin up a fully automated [Datadog Network Device Monitoring](https://docs.datadoghq.com/network_monitoring/devices/) lab on Google Cloud. The lab runs inside a single GCE VM using [Containerlab](https://containerlab.dev/) + [vrnetlab](https://github.com/srl-labs/vrnetlab) to emulate five real Cisco CSR1000v routers, and demonstrates:

- **NDM / SNMP polling** of 5 Cisco CSR1000v routers (`cisco-csr1000v` profile)
- **NetworkPath** — true data-plane multi-hop traceroute, **up to 5 router hops**
- **iBGP chain** over the 5 routers with an FRR eBGP peer simulating the Internet
- **Friendly display names** in the Datadog UI (`csr1-bkk-edge`, `csr5-cnx-endpoint`, etc.) via `/etc/hosts` + `destination_service`
- **Load-test script** (`loadtest.sh`) to exercise the CSR1000v's unlicensed ~100 Kbps data-plane throttle — generates measurable loss + latency that shows up in NetworkPath graphs
- **Datadog events** automatically posted around each load-test run so they appear as annotations on NetworkPath timelines

Any site is supported: `datadoghq.com` (US1), `us3.datadoghq.com`, `us5.datadoghq.com`. The API key is loaded from a local `.env` file; `dd_site` is validated by Terraform to reject other values.

---

## Architecture

### GCP infrastructure

```
┌────────────────────────────────────────────────────┐
│  GCP Project — asia-southeast1                     │
│  ┌──────────────────────────────────────────────┐  │
│  │  VPC: ddlab-ndm-vpc  (10.100.0.0/24)         │  │
│  │  ┌────────────────────────────────────────┐  │  │
│  │  │  GCE VM: ddlab-ndm                     │  │  │
│  │  │  n2-standard-8  (8 vCPU / 32 GB RAM)   │  │  │
│  │  │  Debian 12, 200 GB SSD, nested-KVM ON  │  │  │
│  │  │                                        │  │  │
│  │  │  ┌─────────────────────────────────┐   │  │  │
│  │  │  │ Docker bridge 172.20.20.0/24    │   │  │  │
│  │  │  │ Containerlab topology (below)   │   │  │  │
│  │  │  └─────────────────────────────────┘   │  │  │
│  │  └────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────┘  │
│  Cloud Router → Cloud NAT (outbound only)          │
│  IAP SSH tunnel (no public IP)                     │
└────────────────────────────────────────────────────┘
```

### Lab topology inside the VM

```
                            ┌─ Agent mgmt  (172.20.20.5 / eth0)
                            │
dd-agent (Datadog Agent) ───┤
                            │
                            └─ Data-plane (10.99.0.2/30 / eth2)
                                       │
bgp-peer (FRR, 172.20.20.6)   ─ eBGP ─ CSR1    (172.20.20.10, Gi4 10.99.0.1)
                                       │   Lo0 = 10.100.1.1
                                       │ iBGP over 10.0.12.0/30 (Gi3 ↔ Gi2)
                                       ▼
                             CSR2      (172.20.20.11)
                             Lo0 = 10.100.2.1
                                       │ iBGP over 10.0.23.0/30 (Gi3 ↔ Gi2)
                                       ▼
                             CSR3      (172.20.20.12)
                             Lo0 = 10.100.3.1
                                       │ iBGP over 10.0.34.0/30 (Gi3 ↔ Gi2)
                                       ▼
                             CSR4      (172.20.20.14)
                             Lo0 = 10.100.4.1
                                       │ iBGP over 10.0.45.0/30 (Gi3 ↔ Gi2)
                                       ▼
                             CSR5      (172.20.20.15)
                             Lo0 = 10.100.5.1
```

- **eth2 on dd-agent is the key** — it's a direct data-plane veth to CSR1 Gi4 in the **global** routing table (bypassing vrnetlab's SLiRP-NAT'd `Mgmt-intf` VRF on Gi1). Without it, ICMP probes for the 10.100.X.1 loopbacks get NAT'd back to the mgmt bridge and never reach downstream routers.
- **Static routes** on every CSR + iBGP work together as belt-and-suspenders so 5-hop paths converge quickly on a cold boot.
- **RAM**: each CSR1000v VM is started with `env: RAM: "4096"` (4 GB) — 5 × 4 = 20 GB of QEMU, fits in 32 GB with headroom for Docker/OS/agent.

### NetworkPath targets

The agent emits **8 NetworkPath traces**:

| Display name (`hostname`) | `destination_service` | Expected hops | Protocol |
|---|---|---|---|
| `csr1-bkk-edge-mgmt` | `CSR1-BKK-EDGE (mgmt)` | 1 | TCP/22 |
| `csr2-wan-transit-mgmt` | `CSR2-WAN-TRANSIT (mgmt)` | 1 | TCP/22 |
| `csr3-cnx-edge-mgmt` | `CSR3-CNX-DC-EDGE (mgmt)` | 1 | TCP/22 |
| `csr1-bkk-edge` | `CSR1-BKK-EDGE (loopback)` | 1 | ICMP |
| `csr2-wan-transit` | `CSR2-WAN-TRANSIT (loopback)` | 2 | ICMP |
| `csr3-cnx-edge` | `CSR3-CNX-DC-EDGE (loopback)` | 3 | ICMP |
| `csr4-cnx-access` | `CSR4-CNX-ACCESS` | 4 | ICMP |
| `csr5-cnx-endpoint` | `CSR5-CNX-ENDPOINT` | 5 | ICMP |

The three `-mgmt` paths traverse only the Docker bridge (1 hop) and act as a reachability baseline. The five loopback paths traverse the CSR data-plane chain for real multi-hop observability.

---

## Prerequisites

1. GCP project with Compute + IAP APIs enabled
2. Terraform ≥ 1.5 and `gcloud` CLI authenticated (`gcloud auth login` + `gcloud auth application-default login`)
3. A valid licensed `csr1000v-universalk9.*.qcow2` image (e.g. `16.07.01-serial`) — required by vrnetlab to build the Cisco image
4. Datadog API key (any US site), stored locally in `.env`

---

## Quick start

The lab auto-provisions a GCS bucket that caches the licensed Cisco CSR1000v qcow2 **and** the pre-built vrnetlab Docker image. After the one-time qcow2 upload, every subsequent `terraform destroy && terraform apply` cycle will re-create the VM and automatically deploy a fully working 5-CSR lab in ~10 minutes — no manual SSH required.

### First-time setup (qcow2 not yet uploaded)

```bash
cd ndm/ddlab-automation/terraform

# 1. Write your Datadog API key to .env (git-ignored)
cat > .env <<EOF
DD_API_KEY=<your 32-char Datadog API key>
EOF

# 2. Copy + customise vars (GCP project, SSH key, device passwords)
cp terraform.tfvars.example terraform.tfvars
#    Edit: gcp_project, gcp_zone, gce_service_account, ssh_public_key,
#    snmp/device passwords, dd_site.

# 3. Apply — creates VPC + NAT + GCE VM + cache bucket
set -a && source .env && set +a
export TF_VAR_dd_api_key="$DD_API_KEY"
terraform init
terraform apply

# 4. Upload the licensed qcow2 to the cache bucket (ONE TIME, ever)
#    Terraform printed the exact command as `cold_start_upload_command`:
gsutil cp <path-to-csr1000v-universalk9.16.07.01-serial.qcow2> \
  gs://$(terraform output -raw image_cache_bucket)/csr1000v.qcow2

# 5. Kick the VM so the startup script picks up the qcow2,
#    builds the vrnetlab image, caches it back to the bucket,
#    and auto-deploys the 5-CSR lab. `terraform output` already
#    printed the exact commands as `cold_start_upload_command`,
#    or extract the values yourself:
PROJECT=$(terraform console <<<'var.gcp_project' | tr -d '"')
ZONE=$(terraform output -raw instance_zone)
NAME=$(terraform output -raw instance_name)

gcloud compute instances reset "$NAME" --zone="$ZONE" --project="$PROJECT"

# 6. Monitor — lab fully deployed ~15 min after reset (first-time) or
#    ~10 min on subsequent applies (cached image, skips build)
gcloud compute ssh "labuser@$NAME" --zone="$ZONE" --project="$PROJECT" \
  --tunnel-through-iap \
  -- 'tail -f /var/log/ddlab-deploy.log'
```

After this first-time run, the bucket now contains:

```
gs://<project>-<lab_name>-cache/csr1000v.qcow2                      ~ 850 MB
gs://<project>-<lab_name>-cache/vrnetlab-cisco_csr1000v.tar.gz      ~ 1 GB
```

### Steady-state (re-run any time — fully automatic)

```bash
cd ndm/ddlab-automation/terraform

# Everything is remembered in the cache bucket — no qcow2 upload needed.
set -a && source .env && set +a
export TF_VAR_dd_api_key="$DD_API_KEY"
terraform apply         # ~70 s to return (creates VM + bucket + IAM)
# Startup script then:
#   - detects cached image tarball in the bucket
#   - docker loads it (~30 s)
#   - pre-seeds the cisco-csr1000v SNMP profile
#   - runs containerlab deploy (5 CSRs, ~7 min to CVAC-4-CONFIG_DONE)
#   - configures eth2, MASQUERADE, /etc/hosts, validates
# Total from `terraform apply` to healthy 5-CSR lab: ~12 min. Hands-off.
```

**Measured timings** on `n2-standard-8` with a warm bucket cache (from the
smoke-test runs during this lab's development):

| Step | Wall-clock time |
|---|---|
| `terraform destroy` | ~95 s (VM + VPC torn down; bucket preserved by design) |
| `terraform apply` | ~75 s (VM + bucket + IAM + firewalls; returns to prompt) |
| Startup script → STAGE 13 → `deploy-lab.sh` kick-off | ~1-2 min |
| `containerlab deploy` + 5 CSRs booting in parallel | ~7-8 min |
| Post-deploy fixes (host route, /etc/hosts, profile verify) | < 10 s |
| **Total destroy → apply → fully working lab** | **~12-13 min** |

### Tear down vs keep cache

```bash
# Normal destroy — keeps the cache bucket (RECOMMENDED)
terraform destroy
```

`terraform destroy` intentionally **fails on the `google_storage_bucket` resource**
with:

```
Error: Error trying to delete bucket <project>-<lab_name>-cache
       containing objects without `force_destroy` set to true
```

This is **by design** — it prevents the ~2 GB cached qcow2 + built image
from being accidentally wiped. All OTHER resources (VM, VPC, NAT, firewalls,
IAM binding) are destroyed successfully before the bucket error. Your next
`terraform apply` recreates the VM + bucket IAM, and the startup script
reuses the cached image.

```bash
# Full wipe, including cache (next apply will require re-uploading the qcow2)
terraform destroy -var image_cache_force_destroy=true
```

### What `terraform apply` → startup script does

```
STAGE 13 (auto-provision):
  ┌───────────────────────────────────────────────────────────────┐
  │ (a) gs://<bucket>/vrnetlab-cisco_csr1000v.tar.gz exists?      │
  │     → gsutil cp + docker load  (~30 s)   ← normal case         │
  │                                                                │
  │ (b) gs://<bucket>/csr1000v.qcow2 exists?                       │
  │     → download + build vrnetlab image (~10 min)                │
  │     → docker save + upload .tar.gz back to cache               │
  │                                                                │
  │ (c) neither → log upload instructions + stop                   │
  │     (first-time only; a `gcloud compute instances reset`       │
  │      after `gsutil cp` resumes from here)                      │
  └───────────────────────────────────────────────────────────────┘

If (a) or (b) succeeds, STAGE 13 kicks `systemd-run --unit=ddlab-deploy`
which runs /opt/ddlab/scripts/deploy-lab.sh in the background:

  1. install-csr1000v-profile.sh       ← pre-deploy; seeds user profile
                                          dir BEFORE the agent starts so
                                          the core SNMP loader has the
                                          profile cached on first init —
                                          avoids an agent restart that
                                          would drop the clab eth2 veth
  2. containerlab deploy               ← 5 CSRs + FRR + dd-agent + eth2
  3. wait_for_boot (CVAC-4-CONFIG_DONE)
  4. host route 10.0.0.0/8 via 172.20.20.5 + MASQUERADE on eth2
  5. install-csr1000v-profile.sh       ← re-run as a safety net (SIGHUP
                                          if the profile was already OK)
  6. populate /etc/hosts in dd-agent   ← NetworkPath display names
  7. validate.sh smoke test
```

### Verify in Datadog

- **NDM devices** → `https://<site>/devices`, filter `device_namespace:lab-th` → 5 CSR1000v routers
- **NetworkPath** → `https://<site>/network/path`, filter `path_type:data-plane` → 5 multi-hop paths with 1–5 hops each
- **Topology Map** → `https://<site>/devices/topology` → CDP-discovered chain

---

## Terraform variables

See `variables.tf` for the complete list. Key ones:

| Variable | Example | Notes |
|---|---|---|
| `dd_api_key` | sourced from `.env` via `TF_VAR_dd_api_key` | **Prompted interactively** if unset |
| `dd_site` | `us3.datadoghq.com` | Validated — only `datadoghq.com`, `us3.datadoghq.com`, `us5.datadoghq.com` allowed |
| `gcp_project` | `my-gcp-project` | Must have Compute + IAP APIs |
| `gcp_zone` | `asia-southeast1-a` | Must support N2 Intel for nested KVM |
| `machine_type` | `n2-standard-8` | 5-CSR lab needs ≥ 8 vCPU / 32 GB |
| `csr_image_tag` | `vrnetlab/cisco_csr1000v:16.07.01` | Set to match the tag your `build-images.sh` produced |
| `csr_mgmt_ip` … `csr5_mgmt_ip` | 172.20.20.10 – .15 | Defaults are fine |
| `snmp_v3_user` / `snmp_v3_auth_pass` / `snmp_v3_priv_pass` | `dduser` / `LabAuth@2024!` / `LabPriv@2024!` | Used by the CSR startup-configs and the agent SNMPv3 config |

`pan_*` and `f5_*` variables remain for backward compatibility with older tfvars files but are **not used** — the topology is CSR-only now.

---

## Scripts (rendered into `/opt/ddlab/scripts/` on the VM)

| Script | Purpose |
|---|---|
| `build-images.sh` | Build vrnetlab Cisco CSR1000v image from the uploaded qcow2, then auto-upload the built image tarball to the GCS cache bucket so future apply cycles skip the build (~10 min). |
| `deploy-lab.sh` | **Idempotent end-to-end deploy.** Checks `docker ps` for running CSRs; if they're missing, cleans any stale clab state and runs `containerlab deploy`. Pre-seeds the SNMP profile before clab deploys the agent (no restart), waits for CSRs to boot, sets up host routes + MASQUERADE, populates `/etc/hosts`, runs validate. |
| `install-csr1000v-profile.sh` | Copy the `cisco-csr1000v` SNMP profile + deps into the agent's user profile dir. Works **pre-deploy** (extracts from the agent image via a throwaway container — doesn't need the agent running) and **post-deploy** (extracts via `docker exec` on the running agent). Only does a `docker restart` if the agent is already cached with `"unknown profile"` errors; otherwise SIGHUP. |
| `loadtest.sh` | hping3-based load generator (`steady` / `trickle` / `burst` / `flood` / `overload`) — see [Load testing](#load-testing). Posts start/end events to Datadog so each test window appears as an annotation on NetworkPath graphs. |
| `validate.sh` | Smoke test: containers running, agent healthy, SNMP reachable on all 5 CSRs. |
| `simulate-packet-loss.sh` | tc-netem packet loss on a router's transit interfaces. |
| `simulate-cpu-stress.sh` | Spike CPU on a CSR's QEMU VM. |
| `simulate-network-faults.sh` | Menu-driven fault injection wrapper around the simulate-* scripts. |

---

## Load testing

The lab ships with a ready-to-run load generator that stresses the CSR1000v's unlicensed ~100 Kbps data-plane throttle, producing measurable loss + latency visible in NetworkPath dashboards.

```bash
sudo bash /opt/ddlab/scripts/loadtest.sh [target] [mode] [duration_secs]
```

### Targets

`csr2` / `csr-wan-transit` (default), `csr3` / `csr-cnx-edge`, `csr4` / `csr-cnx-access`, `csr5` / `csr-cnx-endpoint`, or any IP.

### Modes

| Mode | Target rate | Bandwidth | vs 100 Kbps cap | What you'll see |
|---|---|---|---|---|
| `steady` | 100 pps × 100 B | ~80 Kbps | Under cap | Flat latency, 0% loss |
| `trickle` | 150 pps × 100 B | ~150 Kbps | **1.5× over** | Sawtooth latency (2-9× baseline), 0% visible loss — classic brownout signature |
| `burst` | 1 000 pps × 100 B | ~800 Kbps | **8× over** | Clear loss + latency spikes |
| `flood` | hping3 `--flood` | host CPU bound | **100×+ over** | Heavy loss |
| `overload` | 10 000 pps × 1 KB | ~80 Mbps | **800× over** | Near-total loss (>99%), long recovery |

Every run posts a `LoadTest START` and `LoadTest END` Datadog event tagged `source:ddlab-ndm`, `test:loadtest`, `target:<target>`, `mode:<mode>` — they appear as annotations on NetworkPath graphs.

### Demo sequence

```bash
# Green baseline
sudo bash /opt/ddlab/scripts/loadtest.sh csr-wan-transit steady 120

# Subtle brownout (most production-like)
sudo bash /opt/ddlab/scripts/loadtest.sh csr-wan-transit trickle 120

# Clear degradation
sudo bash /opt/ddlab/scripts/loadtest.sh csr-wan-transit burst 90

# Red alert
sudo bash /opt/ddlab/scripts/loadtest.sh csr-wan-transit overload 60
```

### Long-running test in the background

```bash
sudo systemd-run --unit=ddlab-loadtest \
  --description="Steady 30min" \
  --property=StandardOutput=append:/var/log/ddlab-loadtest.log \
  --property=StandardError=append:/var/log/ddlab-loadtest.log \
  /bin/bash /opt/ddlab/scripts/loadtest.sh csr-wan-transit steady 1800

# Monitor
sudo tail -f /var/log/ddlab-loadtest.log
sudo systemctl status ddlab-loadtest.service
# Stop early
sudo systemctl stop ddlab-loadtest.service
```

---

## SNMP profile handling

The `cisco-csr1000v` profile (sysObjectID `1.3.6.1.4.1.9.1.1537`) ships with Datadog's **Python** SNMP integration but **not** with the core (Go) SNMP loader. This lab uses the **core loader** for stability (the Python loader hits `RuntimeError: There is no current event loop in thread 'Dummy-N'` when polling ≥4 instances concurrently on recent agent versions, silently dropping most polls).

The bootstrap does two things to bridge the gap:

1. **Pre-deploy seed** — `install-csr1000v-profile.sh` runs **before** `containerlab deploy` brings the agent up. It extracts `cisco-csr1000v.yaml` + transitive deps (`_base.yaml`, `_base_cisco.yaml`, `_cisco-generic.yaml`, `_cisco-metadata.yaml`, `_generic-*.yaml`, `_std-*.yaml`) from the Datadog agent image (via a throwaway container — doesn't require the agent to be running) into `/opt/ddlab/conf.d/snmp.d/profiles/`, which is bind-mounted into the agent as `/etc/datadog-agent/conf.d/snmp.d/profiles/`. When the agent container starts, the core SNMP loader finds and caches the profile on first init — **no restart, no eth2 dance**.

2. **Post-deploy safety net** — the same script runs again after `containerlab deploy`. On a healthy agent it's a SIGHUP no-op; if for some reason the agent came up with stale profile state, the script detects `"unknown profile \"cisco-csr1000v\""` in `agent status` and `docker restart`s the agent (user will need a subsequent `containerlab destroy && deploy` to reattach `eth2` — this branch should never fire in normal operation).

The SNMP `instances.yaml` then uses:

```yaml
loader: core
profile: cisco-csr1000v
```

And the agent reports 5 instances with IDs like `snmp:lab-th:172.20.20.{10,11,12,14,15}:<hash>` — **all `[OK]` or `[WARNING]`** (WARNING is cosmetic: CSR1000v doesn't populate every OID the bundled profile walks).

To re-apply manually (idempotent, safe to rerun any time):

```bash
sudo bash /opt/ddlab/scripts/install-csr1000v-profile.sh
```

---

## Troubleshooting

See [TROUBLESHOOTING.md](TROUBLESHOOTING.md) for a full operational playbook. A few quick ones:

### Data-plane NetworkPath paths drop to 0–40% reachability

Usually means `eth2` on the dd-agent container got wiped (happens if someone `docker restart`s the agent — containerlab veth pairs are tied to the initial `clab deploy`).

```bash
# Diagnose
sudo docker exec clab-ddlab-ndm-dd-agent ip -br addr show eth2
# "Device eth2 does not exist." → needs redeploy

# Fix — just re-run deploy-lab.sh; it's idempotent and will detect no
# CSRs running, clean stale state, redeploy, and re-pre-seed the profile
sudo bash /opt/ddlab/scripts/deploy-lab.sh
```

### NDM shows fewer than 5 devices (rare — shouldn't happen with current scripts)

The pre-seed strategy in `deploy-lab.sh` installs the SNMP profile BEFORE the agent container starts, so the core loader has it cached on first init. If you still see fewer than 5 devices:

```bash
# Diagnose
sudo docker exec clab-ddlab-ndm-dd-agent agent status 2>&1 \
  | grep -E "snmp:lab-th|unknown profile|var_binds"

# Healthy output — 5 instances, IDs like:
#   snmp:lab-th:172.20.20.{10,11,12,14,15}:<hash>  [OK]
#   Last Successful Execution Date: <recent>

# If you see "unknown profile cisco-csr1000v", re-install + restart:
sudo bash /opt/ddlab/scripts/install-csr1000v-profile.sh

# (If the install triggers an agent restart, eth2 is dropped — follow
#  up with deploy-lab.sh to fix that)
sudo bash /opt/ddlab/scripts/deploy-lab.sh
```

### Load test seems to fail before running

`hping3` and friends are installed by a clab `exec:` hook on the agent, which only fires on `containerlab deploy`. After a `docker restart` they're gone. Quick reinstall:

```bash
sudo docker exec clab-ddlab-ndm-dd-agent bash -c \
  "apt-get -qq update && apt-get -qq install -y hping3 traceroute iputils-ping curl snmp"
```

Or just re-run `deploy-lab.sh` — it does this automatically on every invocation.

---

## Destroy

```bash
cd ndm/ddlab-automation/terraform
terraform destroy
```

This removes the GCE VM, VPC, NAT, firewalls, and IAM binding. By design, **`terraform destroy` intentionally errors on the image-cache bucket** if it contains objects:

```
Error: Error trying to delete bucket <project>-<lab_name>-cache
       containing objects without `force_destroy` set to true
```

Everything else is destroyed first — only the bucket is left intact. This is a safety feature: the bucket's ~2 GB cached qcow2 + built vrnetlab image is expensive to rebuild, so `destroy` protects it by default. Next `terraform apply` recreates the VM/network and instantly reuses the cached image.

If you really want to wipe the cache too (e.g. you rotated the qcow2 or want a completely fresh start):

```bash
terraform destroy -var image_cache_force_destroy=true
```

Datadog devices in `device_namespace:lab-th` will age out of the NDM inventory within ~24 h automatically.

---

## File layout

```
ndm/ddlab-automation/
├── README.md                  ← you are here
├── TROUBLESHOOTING.md         ← operational playbook
├── NETWORK-OBSERVABILITY.md   ← product walkthrough & demo script
├── scripts/
│   └── startup.sh.tpl         ← Terraform templatefile(); renders all
│                                 on-VM configs + scripts
└── terraform/
    ├── main.tf                ← GCP resources (VPC, NAT, GCE, FW)
    ├── variables.tf           ← All tunables
    ├── outputs.tf             ← SSH + Datadog UI URLs, Geomap metadata
    ├── terraform.tfvars.example
    └── .env                   ← DD_API_KEY (git-ignored)
```
