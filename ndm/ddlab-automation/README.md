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

## Who this is for

This repo is a **Datadog SE / Solutions Architect demo asset** for Network Observability conversations. Spin it up once, hook a Datadog org to it, and you have a self-contained, customer-safe sandbox where you can demonstrate every NDM + NetworkPath capability without touching any real network gear.

Typical use cases:

| Audience | Demo |
|---|---|
| Network engineering team evaluating NDM | "Plug in any router with SNMP and you'll see this view in 5 minutes" — show the 5-CSR fleet view, profile-driven metrics, BGP session table, interface stats. |
| NetOps / SRE evaluating NetworkPath | "We can pinpoint *which hop* is slow." Run Scenario 1 (latency on CSR2) and the customer sees hop-2 RTT spike in real time. |
| Procurement asking "what does this look like at scale?" | The lab uses the **same Datadog Agent + same SNMP profiles** that real production deployments use — point at this and at their fleet without changing anything. |
| Pre-sales POVs (proof-of-value) | The whole stack is reproducible from a single `terraform apply`. Hand the repo to a prospect's net-eng team to extend with their own gear. |

### Why a containerlab-based lab (vs. our hosted demo)

- **Real Cisco IOS-XE** — vrnetlab boots the full CSR1000v IOS-XE QEMU VM, not a simulator. SNMP responses, BGP behavior, CDP neighbors, and traceroute time-exceeded handling are all genuine.
- **Repeatable** — one `terraform apply`; no shared state with other SEs.
- **Fault injection** — `tc netem` lets you reproduce latency, packet loss, BGP flap, link failure on demand. See [`NETWORK-OBSERVABILITY.md`](NETWORK-OBSERVABILITY.md) for the full demo playbook.
- **Customer-safe** — runs entirely inside one GCE VM (no public IPs, IAP-tunnel SSH); the prospect can `terraform destroy` and the only thing left is a 2 GB GCS cache bucket for the next apply.

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

## Key concepts (for SEs)

This section explains the Datadog products this lab exercises so you can speak to the "why" in customer conversations.

### Network Device Monitoring (NDM)

NDM polls SNMP-capable network devices (routers, switches, firewalls, load balancers, wireless controllers, …) on a schedule and surfaces them in [`/devices`](https://docs.datadoghq.com/network_monitoring/devices/) as a fleet inventory with metrics, interface state, BGP peers, ACL hits, and more.

The Datadog Agent's SNMP check resolves the device's `sysObjectID` against a [vendor profile](https://docs.datadoghq.com/network_monitoring/devices/profiles/) which declares which OIDs to walk and how to expose them as metrics, tags, and metadata. There are 200+ profiles bundled with the agent (Cisco, Arista, Juniper, F5, Palo Alto, Fortinet, Aruba, Meraki, …) and you can [author your own](https://docs.datadoghq.com/network_monitoring/devices/profile_format/) for niche devices.

**Key docs:**

- [NDM overview](https://docs.datadoghq.com/network_monitoring/devices/) — what it is + how it works
- [Setup guide (Linux Agent)](https://docs.datadoghq.com/network_monitoring/devices/setup/) — agent install, snmp.d configs
- [SNMP profiles index](https://docs.datadoghq.com/network_monitoring/devices/profiles/) — list of bundled profiles + sysObjectIDs
- [Profile format](https://docs.datadoghq.com/network_monitoring/devices/profile_format/) — write/extend a profile
- [Autodiscovery (subnet scanner)](https://docs.datadoghq.com/network_monitoring/devices/snmp_scanner/) — sweep a CIDR + auto-detect profiles
- [SNMP Traps](https://docs.datadoghq.com/network_monitoring/devices/snmp_traps/) — receive linkUp/linkDown/BGP traps
- [NetFlow](https://docs.datadoghq.com/network_monitoring/devices/netflow/) — flow-based traffic analysis
- [Topology Map (CDP/LLDP)](https://docs.datadoghq.com/network_monitoring/devices/topology_map/) — auto-drawn adjacency view

### NetworkPath

[NetworkPath](https://docs.datadoghq.com/network_monitoring/network_path/) is hop-by-hop traceroute as a continuous metric. The agent runs `traceroute` (TCP, UDP, or ICMP) toward defined destinations on an interval; for each probe it records every hop's IP, RTT, and reachability. Datadog stores this as time-series so you can ask:

- "What's the average RTT to hop 3 over the last 24 h?"
- "Which path's reachability has dropped below 99%?"
- "Did the path *change* (new hop appeared) at the same time latency spiked?"

This is the answer to the "**which hop is slow?**" question that historically required ticketing the network team and waiting for a manual `traceroute` from a remote VPN-jumped box.

**Key docs:**

- [NetworkPath overview](https://docs.datadoghq.com/network_monitoring/network_path/) — concepts + use cases
- [Setup](https://docs.datadoghq.com/network_monitoring/network_path/setup/) — agent config + system-probe requirements
- [Using NetworkPath](https://docs.datadoghq.com/network_monitoring/network_path/using_network_path/) — UI walkthrough
- [Cloud Network Monitoring](https://docs.datadoghq.com/network_monitoring/cloud_network_monitoring/) — adjacent product for cloud-native flow telemetry

### How NDM and NetworkPath complement each other

| Question the customer asks | Product that answers it |
|---|---|
| "Is **the device** healthy?" (CPU, memory, fan, interface counters, BGP state) | **NDM** — SNMP polling on a per-device basis |
| "Is **the path** through these devices healthy?" (RTT, loss, hop changes) | **NetworkPath** — traceroute-as-metric, agent-side |
| "Is **the link** between two specific devices saturated?" | **NDM** interface throughput counters + **NetFlow** for top-talkers |
| "Did **routing converge** correctly after that change?" | **NDM** BGP table snapshots + Topology Map + **NetworkPath** path-change events |

Both products send to the same Datadog backend, share tags (`env`, `service`, `team`, `device_namespace`), and can be cross-referenced in a single dashboard.

### SNMP loaders — `core` vs `python` (gotcha)

The Datadog Agent ships **two** SNMP collection loaders:

- **`loader: python`** — the original integration (Python, pysnmp). Bundles the full set of vendor profiles in `embedded/lib/.../snmp/data/default_profiles/`.
- **`loader: core`** — the newer Go-based loader, much faster + lower memory, used by [SNMP autodiscovery](https://docs.datadoghq.com/network_monitoring/devices/snmp_scanner/) by default. Has a smaller compiled-in profile set.

This lab uses **`loader: core` + an explicit `profile: cisco-csr1000v`** because:

- The Python loader has a known bug on agent 7.78+: `RuntimeError: There is no current event loop in thread 'Dummy-N'` when polling 4+ instances concurrently. Drops the 4th+ poll silently.
- The core loader is rock-solid but doesn't ship `cisco-csr1000v.yaml`. Solution: copy the bundled profile from the Python integration's data dir into `/etc/datadog-agent/conf.d/snmp.d/profiles/` (a [user profile dir](https://docs.datadoghq.com/network_monitoring/devices/profile_format/?tab=customprofiles) the core loader reads). Done automatically by `install-csr1000v-profile.sh`.

If you're doing a discovery call and a customer asks "should we use core or python loader?", the right answer in 2026 is:

> "Core for new deployments — it's faster, scales further, and is the only loader that supports modern features like NetFlow integration and SNMP traps autodiscovery. The bundled profile set covers ~95% of what we see in the field; for the remaining 5% (or anything custom), drop a YAML file in the user profile dir and the core loader picks it up."

### True multi-hop NetworkPath inside a containerlab

Most "demo NDM" environments only show single-hop reachability because all the simulated devices sit on the same Docker bridge (`172.20.20.0/24` here). Real customer networks have **multi-hop** paths — that's the whole point of NetworkPath. To make this lab reproduce that:

- An extra **data-plane veth** is wired between `dd-agent:eth2` and `csr1:Gi4` on `10.99.0.0/30`. This sits in the CSR1's **global** routing table (not the SLiRP-NAT'd `Mgmt-intf` VRF that Gi1 uses).
- The agent's `ip route 10.0.0.0/8 via 10.99.0.1 dev eth2` directs all data-plane probes through CSR1's Gi4 → CSR1 forwards via Gi3 → CSR2 → Gi3 → CSR3 → Gi3 → CSR4 → Gi3 → CSR5 (each loopback `10.100.X.1` is a one-hop-deeper destination).
- This is the same pattern a customer would use for "NetworkPath through a private MPLS overlay" — the agent has a routed path into the data plane, not just management connectivity.

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

## Integration snippets — lift these into your customer's environment

Everything the lab installs is standard Datadog Agent config. The snippets below are simplified versions of what gets generated at `/opt/ddlab/conf.d/snmp.d/` and `/opt/ddlab/conf.d/network_path.d/` on the lab VM — you can lift them straight into a real customer Agent.

### 1. SNMP — single device with explicit profile

`/etc/datadog-agent/conf.d/snmp.d/conf.yaml`

```yaml
init_config:

instances:
  - ip_address: 10.10.20.5            # router mgmt IP
    snmp_version: 3
    user: dduser
    authProtocol: SHA
    authKey: <auth-pass>
    privProtocol: AES
    privKey: <priv-pass>
    loader: core                       # see "Key concepts" — use core
    profile: cisco-csr1000v             # explicit; skips autodetect
    tags:
      - "device_namespace:prod-network"
      - "site:bkk-dc1"
      - "team:netops"
      - "tier:wan-edge"
```

[Reference: SNMP integration setup](https://docs.datadoghq.com/network_monitoring/devices/setup/?tab=linux)

### 2. SNMP — autodiscovery sweep of a subnet

`/etc/datadog-agent/datadog.yaml`

```yaml
network_devices:
  namespace: prod-network               # appears as device_namespace tag
  autodiscovery:
    enabled: true
    workers: 10
    discovery_interval: 300             # seconds — re-scan every 5 min
    use_deduplication: true
    configs:
      - network_address: 10.10.20.0/24
        snmp_version: 3
        user: dduser
        authProtocol: SHA
        authKey: <auth-pass>
        privProtocol: AES
        privKey: <priv-pass>
```

The agent issues `GetRequest sysObjectID.0` against every IP in the subnet, matches against bundled profiles, and starts polling automatically. Devices that don't respond (or whose sysObjectID doesn't match any profile) are ignored quietly.

[Reference: SNMP autodiscovery / scanner](https://docs.datadoghq.com/network_monitoring/devices/snmp_scanner/)

> **Note on this lab:** autodiscovery is intentionally **disabled** here in favor of static instances — the core loader's autodiscovery doesn't ship the cisco-csr1000v profile and would error. In production with whatever-vendor devices your customer runs, autodiscovery is usually the right starting point.

### 3. NetworkPath — multi-hop traceroute target

`/etc/datadog-agent/conf.d/network_path.d/conf.yaml`

```yaml
instances:
  - hostname: csr5-cnx-endpoint         # display name in UI
    protocol: ICMP                       # or TCP / UDP
    source_service: dd-lab-agent         # appears in "Service" column
    destination_service: CSR5 endpoint   # friendly destination label
    tags:
      - "path_name:agent-to-cnx-endpoint"
      - "path_type:data-plane"
      - "expected_hops:5"
      - "team:netops"
    max_ttl: 12
    traceroute_queries: 3                # number of traceroutes per check run
    min_collection_interval: 60          # seconds
```

[Reference: NetworkPath setup](https://docs.datadoghq.com/network_monitoring/network_path/setup/) — also covers the `system-probe.yaml` change required to enable traceroute (this lab does that automatically).

### 4. SNMP traps receiver

`/etc/datadog-agent/datadog.yaml`

```yaml
network_devices:
  snmp_traps:
    enabled: true
    port: 162
    bind_host: 0.0.0.0
    community_strings:
      - <ro-community>
    users:                                # SNMPv3 trap users
      - username: dduser
        authKey: <auth-pass>
        authProtocol: SHA
        privKey: <priv-pass>
        privProtocol: AES
```

Then on each device: `snmp-server host <agent-ip> version 3 priv dduser`. Datadog will index the traps as logs and surface them in the [SNMP Traps Explorer](https://docs.datadoghq.com/network_monitoring/devices/snmp_traps/).

### 5. Custom SNMP profile (extending an existing one)

`/etc/datadog-agent/conf.d/snmp.d/profiles/cisco-csr-bgp.yaml`

```yaml
extends:
  - cisco-csr1000v.yaml      # picks up everything from the bundled profile

metrics:
  - MIB: BGP4-MIB
    table:
      name: bgpPeerTable
      OID: 1.3.6.1.2.1.15.3
    symbols:
      - OID: 1.3.6.1.2.1.15.3.1.2
        name: bgpPeerState
    metric_tags:
      - column:
          OID: 1.3.6.1.2.1.15.3.1.7
          name: bgpPeerRemoteAddr
        tag: bgp_peer_remote
```

Ship this file, point `profile:` at it in `instances.yaml`, and the agent will start emitting `snmp.bgpPeerState` metrics tagged with each remote-peer IP.

[Reference: profile format reference](https://docs.datadoghq.com/network_monitoring/devices/profile_format/)

### 6. Useful saved metric queries

```
# Average device CPU per site
avg:snmp.cpu.usage{device_namespace:lab-th} by {snmp_host,site}

# All interfaces in error state
sum:snmp.ifInErrors{device_namespace:lab-th} by {snmp_host,interface}.as_rate()

# NetworkPath RTT to a specific destination, by hop
avg:datadog.network_path.path.hop_rtt{path_name:agent-to-csr5-cnx-endpoint} by {hop_index,hop_ip_address}

# Path reachability over time
avg:datadog.network_path.path.reachable{path_type:data-plane} by {destination_service}

# BGP peer state (1 = established, others = down)
avg:snmp.cisco.bgpPeerState{device_namespace:lab-th} by {snmp_host,bgp_peer_remote}
```

### 7. Recommended monitor — NetworkPath hop latency

[Datadog Terraform provider](https://registry.terraform.io/providers/DataDog/datadog/latest/docs/resources/monitor) snippet — drop into a customer's monitors-as-code repo:

```hcl
resource "datadog_monitor" "network_path_hop_rtt" {
  name    = "[NetworkPath] Hop RTT degraded on {{path_name.name}}"
  type    = "metric alert"
  query   = "avg(last_5m):avg:datadog.network_path.path.hop_rtt{path_type:data-plane} by {path_name,hop_index} > 100"
  message = <<-EOM
    Hop {{hop_index.name}} on path {{path_name.name}} is averaging
    {{value}} ms over the last 5 min.

    @netops-oncall

    Investigation:
      - Open the path in NetworkPath: https://app.datadoghq.com/network/path
      - Cross-reference the hop's device in NDM (filter on device_ip = hop's IP)
      - Check device CPU / interface counters around the same window
  EOM

  monitor_thresholds {
    warning  = 50
    critical = 100
  }

  tags = ["team:netops", "service:network-path"]
}
```

### 8. Posting Datadog events from a script (used by `loadtest.sh`)

```bash
curl -sS -X POST "https://api.${DD_SITE}/api/v1/events" \
  -H "Content-Type: application/json" \
  -H "DD-API-KEY: ${DD_API_KEY}" \
  -d "{
    \"title\": \"Maintenance window START — core1.bkk-dc1\",
    \"text\":  \"Patching IOS-XE 17.06 → 17.09. Expect ~5 min loss on hop 2.\",
    \"tags\":  [\"source:netops-runbook\", \"target:core1.bkk-dc1\", \"change_type:maintenance\"],
    \"alert_type\": \"info\"
  }"
```

[Reference: Events API](https://docs.datadoghq.com/api/latest/events/)

These events render as flags on the timeline of every dashboard / NetworkPath graph that overlaps the window — invaluable for "did *we* cause this?" investigations.

---

## File layout

```
ndm/ddlab-automation/
├── README.md                  ← you are here — concepts, setup, integration snippets
├── TROUBLESHOOTING.md         ← operational playbook (11 scenarios, diagnose + fix)
├── NETWORK-OBSERVABILITY.md   ← Network Observability demo playbook
│                                (latency, packet loss, BGP flap, link down, CPU
│                                 stress) with monitor recipes + customer demo flow
├── scripts/
│   └── startup.sh.tpl         ← Terraform templatefile(); renders all on-VM
│                                configs + scripts (~2 400 lines, single source
│                                of truth — every change goes here)
└── terraform/
    ├── main.tf                ← GCP resources (VPC, NAT, GCE, FW, image-cache GCS)
    ├── variables.tf           ← All tunables (Datadog site, SNMP creds, CSR mgmt
    │                            IPs, image cache bucket name)
    ├── outputs.tf             ← SSH + Datadog UI URLs, geomap metadata,
    │                            cold-start qcow2 upload command
    ├── terraform.tfvars.example   ← scrubbed example (no real secrets)
    ├── terraform.tfvars       ← your customised vars (.gitignored)
    └── .env                   ← DD_API_KEY only (.gitignored)
```

### Reading order for a new SE

1. **`README.md`** (this file) — what the lab is, how to bring it up, what concepts it demonstrates, copy-pastable integration snippets.
2. **`NETWORK-OBSERVABILITY.md`** — the customer-facing demo playbook. Run through scenarios 1-5 once on your own org before doing it live.
3. **`TROUBLESHOOTING.md`** — keep open in a side tab during demos. The first 6 scenarios cover the operational gotchas you might hit.
4. **`scripts/startup.sh.tpl`** — only when you want to extend the lab (add a vendor, add a scenario, tweak the topology).
