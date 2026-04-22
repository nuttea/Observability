#!/bin/bash
# ============================================================
# startup.sh — Datadog NDM + Network Path Containerlab Lab
# Bootstrap script rendered by Terraform templatefile()
# Runs on first boot as root via GCE startup-script metadata
#
# Stages:
#   1. System deps (Docker, KVM, tooling)
#   2. Containerlab install
#   3. vrnetlab clone
#   4. Render all config files from Terraform variables
#   5. Wait for user to upload VM images and build containers
#   6. Deploy Containerlab topology
#   7. Configure devices (CSR SNMP/BGP, PAN SNMP/ZP, F5 SNMP/HA)
#   8. Configure and start Datadog Agent
#   9. Register Geomap locations via Datadog API
#  10. Validation checks
# ============================================================
set -euo pipefail

LOG=/var/log/ddlab-startup.log
LOCK=/var/run/ddlab-bootstrap.lock
LAB_DIR=/opt/ddlab
VRNL_DIR=/opt/vrnetlab

exec > >(tee -a "$LOG") 2>&1

# Prevent re-run on instance restart
if [ -f "$LOCK" ]; then
  echo "[$(date)] Bootstrap lock exists — skipping (already ran). Remove $LOCK to re-run."
  exit 0
fi

echo "============================================================"
echo "[$(date)] Starting Datadog NDM Lab Bootstrap"
echo "============================================================"

# ── Terraform-injected variables ────────────────────────────
DD_API_KEY="${dd_api_key}"
DD_SITE="${dd_site}"
DD_NAMESPACE="${dd_namespace}"
# US1 uses https://app.datadoghq.com; US3/US5/etc. use https://<site>/ (no "app." prefix)
if [ "$DD_SITE" = "datadoghq.com" ]; then
  DD_APP_URL="https://app.datadoghq.com"
else
  DD_APP_URL="https://$DD_SITE"
fi
LAB_NAME="${lab_name}"
LAB_MGMT_SUBNET="${lab_mgmt_subnet}"
SNMP_COMMUNITY="${snmp_community}"
SNMP_V3_USER="${snmp_v3_user}"
SNMP_V3_AUTH_PASS="${snmp_v3_auth_pass}"
SNMP_V3_PRIV_PASS="${snmp_v3_priv_pass}"
DEVICE_PASSWORD="${device_password}"
CSR_MGMT_IP="${csr_mgmt_ip}"
CSR2_MGMT_IP="${csr2_mgmt_ip}"
CSR3_MGMT_IP="${csr3_mgmt_ip}"
CSR4_MGMT_IP="${csr4_mgmt_ip}"
CSR5_MGMT_IP="${csr5_mgmt_ip}"
IMAGE_CACHE_BUCKET="${image_cache_bucket}"
PAN_MGMT_IP="${pan_mgmt_ip}"
F5_ACTIVE_MGMT_IP="${f5_active_mgmt_ip}"
F5_STANDBY_MGMT_IP="${f5_standby_mgmt_ip}"
AGENT_MGMT_IP="${agent_mgmt_ip}"
GEO_BKK_LAT="${geo_bkk_lat}"
GEO_BKK_LON="${geo_bkk_lon}"
GEO_CNX_LAT="${geo_cnx_lat}"
GEO_CNX_LON="${geo_cnx_lon}"
GEO_BKK_LABEL="${geo_bkk_label}"
GEO_CNX_LABEL="${geo_cnx_label}"
BGP_LOCAL_AS="${bgp_local_as}"
BGP_PEER_AS="${bgp_peer_as}"
CSR_IMAGE="${csr_image_tag}"
PAN_IMAGE="${pan_image_tag}"
F5_IMAGE="${f5_image_tag}"
F5_LICENSE_KEY="${f5_license_key}"

CLAB_NAME="$LAB_NAME"
CLAB_PREFIX="clab-$CLAB_NAME"

# ============================================================
# STAGE 1 — System Dependencies
# ============================================================
echo "[$(date)] STAGE 1: Installing system dependencies..."

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get upgrade -y -o Dpkg::Options::="--force-confdef"
apt-get install -y \
  curl wget git jq python3 python3-pip python3-netaddr \
  qemu-kvm libvirt-daemon-system libvirt-clients \
  bridge-utils cpu-checker net-tools iproute2 \
  traceroute nmap tcpdump iputils-ping \
  openssh-client sshpass expect \
  make build-essential unzip vim

# Verify KVM
echo "[$(date)] Verifying KVM access..."
if [ ! -c /dev/kvm ]; then
  echo "[ERROR] /dev/kvm not found. Nested virtualization may not be enabled on this instance."
  exit 1
fi
kvm-ok && echo "[OK] KVM acceleration available" || echo "[WARN] kvm-ok check had warnings"

# ============================================================
# STAGE 2 — Docker
# ============================================================
echo "[$(date)] STAGE 2: Installing Docker..."

curl -fsSL https://get.docker.com | bash
systemctl enable docker && systemctl start docker
usermod -aG docker labuser
usermod -aG kvm labuser
usermod -aG libvirt labuser

# ============================================================
# STAGE 3 — Containerlab
# ============================================================
echo "[$(date)] STAGE 3: Installing Containerlab..."
echo "deb [trusted=yes] https://apt.fury.io/netdevops/ /" > /etc/apt/sources.list.d/netdevops.list
apt-get update -y -q 2>&1 | tail -2
apt-get install -y containerlab

echo "[$(date)] Containerlab version: $(containerlab version 2>/dev/null | head -1)"

# ============================================================
# STAGE 4 — vrnetlab
# ============================================================
echo "[$(date)] STAGE 4: Cloning vrnetlab..."
git clone https://github.com/srl-labs/vrnetlab.git "$VRNL_DIR" || {
  echo "[$(date)] vrnetlab already cloned, pulling latest..."
  cd "$VRNL_DIR" && git pull
}
chown -R labuser:labuser "$VRNL_DIR"

# ============================================================
# STAGE 5 — Create Lab Directory Structure
# ============================================================
echo "[$(date)] STAGE 5: Creating lab directory structure..."

mkdir -p "$LAB_DIR"/{containerlab,configs,conf.d/snmp.d/profiles,conf.d/network_path.d,scripts}
chown -R labuser:labuser "$LAB_DIR"

# ============================================================
# STAGE 6 — Render Containerlab Topology File
# ============================================================
echo "[$(date)] STAGE 6: Rendering Containerlab topology..."

cat > "$LAB_DIR/containerlab/ndm-lab.clab.yml" << CLAB_EOF
# ============================================================
# Datadog NDM Containerlab Topology — CSR1000v Multi-Hop Chain
# Auto-generated by Terraform startup script
# Lab: $LAB_NAME
#
# Topology (for NetworkPath multi-hop + NDM):
#   dd-agent (172.20.20.5)
#       │  (clab-mgmt bridge)
#       ├── bgp-peer/FRR (172.20.20.6) ── eBGP ── CSR1 (.10, Gi2)
#       ├── CSR1 (.10) ── Gi3 10.0.12.1/30 ── iBGP ── CSR2 (.11, Gi2 10.0.12.2)
#       ├── CSR2 (.11) ── Gi3 10.0.23.1/30 ── iBGP ── CSR3 (.12, Gi2 10.0.23.2)
#       └── CSR3 (.12) loopback 10.100.3.1 (reached via 3-hop path)
# ============================================================
name: $CLAB_NAME

topology:
  defaults:
    network-mode: bridge

  nodes:

    # ── CSR1 — Bangkok DC1 Edge (eBGP to FRR, iBGP to CSR2) ──
    csr:
      kind: vr-csr
      image: $CSR_IMAGE
      startup-config: /opt/ddlab/configs/csr-startup.cfg
      mgmt-ipv4: $CSR_MGMT_IP

    # ── CSR2 — WAN Transit (iBGP to CSR1 and CSR3) ───────────
    csr2:
      kind: vr-csr
      image: $CSR_IMAGE
      startup-config: /opt/ddlab/configs/csr2-startup.cfg
      mgmt-ipv4: $CSR2_MGMT_IP

    # ── CSR3 — Chiang Mai DC2 Edge (iBGP to CSR2) ────────────
    csr3:
      kind: vr-csr
      image: $CSR_IMAGE
      startup-config: /opt/ddlab/configs/csr3-startup.cfg
      mgmt-ipv4: $CSR3_MGMT_IP

    # ── Datadog Agent ─────────────────────────────────────────
    # eth0 = clab-mgmt bridge (172.20.20.5/24, SNMP + autodiscovery)
    # eth1 = (clab auto-assigns if needed; not used here)
    # eth2 = direct data-plane link to CSR1 Gi4 (10.99.0.2/30) —
    #        entry point for multi-hop NetworkPath through CSR1→2→3
    dd-agent:
      kind: linux
      image: gcr.io/datadoghq/agent:latest
      mgmt-ipv4: $AGENT_MGMT_IP
      env:
        DD_API_KEY: "$DD_API_KEY"
        DD_SITE: "$DD_SITE"
        DD_NETWORK_DEVICES_ENABLED: "true"
        DD_SNMP_TRAPS_ENABLED: "true"
        DD_LOGS_ENABLED: "true"
        DD_SYSTEM_PROBE_ENABLED: "true"
        DD_NETWORK_PATH_ENABLED: "true"
      binds:
        - /opt/ddlab/datadog.yaml:/etc/datadog-agent/datadog.yaml
        - /opt/ddlab/system-probe.yaml:/etc/datadog-agent/system-probe.yaml
        - /opt/ddlab/conf.d/snmp.d/:/etc/datadog-agent/conf.d/snmp.d/
        - /opt/ddlab/conf.d/network_path.d/:/etc/datadog-agent/conf.d/network_path.d/
        - /proc:/host/proc:ro
        - /sys:/host/sys:ro
      # Post-deploy: configure eth2 data-plane interface, enable forwarding,
      # MASQUERADE, and install the 10.0.0.0/8 route via CSR1 Gi4. This is
      # what makes multi-hop NetworkPath work — packets enter CSR1 in its
      # GLOBAL routing table (bypassing the SLiRP-NAT'd Mgmt-intf VRF on
      # Gi1), so Cisco iBGP/static routes to CSR2 / CSR3 loopbacks apply.
      # Also populate /etc/hosts so NetworkPath targets display as friendly
      # names in the Datadog UI ("Destination" column) instead of raw IPs.
      exec:
        - ip addr add 10.99.0.2/30 dev eth2
        - ip link set dev eth2 up
        - sysctl -w net.ipv4.ip_forward=1
        - ip route replace 10.0.0.0/8 via 10.99.0.1 dev eth2
        - iptables -t nat -A POSTROUTING -o eth2 -j MASQUERADE
        # Populate /etc/hosts with friendly names for NetworkPath display.
        # One line per host avoids heredoc-indentation issues.
        - sh -c "echo '172.20.20.10 csr1-bkk-edge-mgmt csr-bkk-edge-mgmt.lab.local' >> /etc/hosts"
        - sh -c "echo '172.20.20.11 csr2-wan-transit-mgmt csr-wan-transit-mgmt.lab.local' >> /etc/hosts"
        - sh -c "echo '172.20.20.12 csr3-cnx-edge-mgmt csr-cnx-edge-mgmt.lab.local' >> /etc/hosts"
        - sh -c "echo '172.20.20.14 csr4-cnx-access-mgmt csr-cnx-access-mgmt.lab.local' >> /etc/hosts"
        - sh -c "echo '172.20.20.15 csr5-cnx-endpoint-mgmt csr-cnx-endpoint-mgmt.lab.local' >> /etc/hosts"
        - sh -c "echo '10.100.1.1 csr1-bkk-edge csr-bkk-edge.lab.local' >> /etc/hosts"
        - sh -c "echo '10.100.2.1 csr2-wan-transit csr-wan-transit.lab.local' >> /etc/hosts"
        - sh -c "echo '10.100.3.1 csr3-cnx-edge csr-cnx-edge.lab.local' >> /etc/hosts"
        - sh -c "echo '10.100.4.1 csr4-cnx-access csr-cnx-access.lab.local' >> /etc/hosts"
        - sh -c "echo '10.100.5.1 csr5-cnx-endpoint csr-cnx-endpoint.lab.local' >> /etc/hosts"
        # Install load-testing + diagnostic tools (persistent across clab
        # deploy cycles; wiped on destroy/redeploy which is fine since the
        # exec hook reinstalls them).
        - bash -c "apt-get -qq update >/dev/null && apt-get -qq install -y hping3 traceroute iputils-ping curl jq >/dev/null"

    # ── FRR BGP Peer (Internet simulation — eBGP to CSR1) ────
    bgp-peer:
      kind: linux
      image: frrouting/frr:latest
      mgmt-ipv4: 172.20.20.6
      binds:
        - /opt/ddlab/configs/frr.conf:/etc/frr/frr.conf

    # ── CSR4 — Access router (4th hop, extends chain from CSR3) ──
    # Full Cisco CSR1000v VM. RAM trimmed to 4 GB so all 5 CSRs fit
    # inside the 32 GB GCE VM (5 x 4 GB = 20 GB + overhead).
    csr4:
      kind: vr-csr
      image: $CSR_IMAGE
      startup-config: /opt/ddlab/configs/csr4-startup.cfg
      mgmt-ipv4: $CSR4_MGMT_IP
      env:
        RAM: "4096"

    # ── CSR5 — Endpoint router (5th hop, end of chain) ───────────
    csr5:
      kind: vr-csr
      image: $CSR_IMAGE
      startup-config: /opt/ddlab/configs/csr5-startup.cfg
      mgmt-ipv4: $CSR5_MGMT_IP
      env:
        RAM: "4096"

  links:
    # ── Data-plane: dd-agent eth2 (10.99.0.2) <-> CSR1 Gi4 (10.99.0.1) ──
    # Entry point for NetworkPath multi-hop into the CSR global routing
    # table. Without this, packets arrive on CSR1 Gi1 (Mgmt-intf VRF) and
    # are NAT'd back to the bridge instead of forwarded via Gi2/Gi3.
    - endpoints: ["dd-agent:eth2", "csr:GigabitEthernet4"]
    # ── eBGP: FRR (AS $BGP_PEER_AS) <-> CSR1 Gi2 (AS $BGP_LOCAL_AS) ──
    - endpoints: ["bgp-peer:eth1", "csr:GigabitEthernet2"]
    # ── iBGP: CSR1 Gi3 (10.0.12.1) <-> CSR2 Gi2 (10.0.12.2) ──
    - endpoints: ["csr:GigabitEthernet3", "csr2:GigabitEthernet2"]
    # ── iBGP: CSR2 Gi3 (10.0.23.1) <-> CSR3 Gi2 (10.0.23.2) ──
    - endpoints: ["csr2:GigabitEthernet3", "csr3:GigabitEthernet2"]
    # ── Chain extension: CSR3 Gi3 (10.0.34.1) <-> CSR4 Gi2 (10.0.34.2) ──
    - endpoints: ["csr3:GigabitEthernet3", "csr4:GigabitEthernet2"]
    # ── Chain extension: CSR4 Gi3 (10.0.45.1) <-> CSR5 Gi2 (10.0.45.2) ──
    - endpoints: ["csr4:GigabitEthernet3", "csr5:GigabitEthernet2"]
CLAB_EOF

echo "[$(date)] Containerlab topology written."

# ============================================================
# STAGE 7 — Render Datadog Agent Config
# ============================================================
echo "[$(date)] STAGE 7: Rendering Datadog Agent configs..."

# ── datadog.yaml ────────────────────────────────────────────
cat > "$LAB_DIR/datadog.yaml" << DD_EOF
api_key: $DD_API_KEY
site: $DD_SITE
hostname: ddlab-ndm-agent
logs_enabled: true

network_devices:
  namespace: $DD_NAMESPACE
  # SNMP autodiscovery disabled: the core/Go loader it uses doesn't ship
  # the cisco-csr1000v profile (sysObjectID 1.3.6.1.4.1.9.1.1537), which
  # causes every discovered instance to error with "unknown profile" or
  # "no profiles found for sysObjectID". We rely on the static SNMP
  # instances in conf.d/snmp.d/instances.yaml (rendered below) with the
  # Python loader, which has all bundled vendor profiles available.
  autodiscovery:
    enabled: false
  snmp_traps:
    enabled: true
    port: 162
    bind_host: 0.0.0.0
    community_strings:
      - $SNMP_COMMUNITY
    users:
      - username: $SNMP_V3_USER
        authKey: $SNMP_V3_AUTH_PASS
        authProtocol: SHA
        privKey: $SNMP_V3_PRIV_PASS
        privProtocol: AES
  netflow:
    enabled: true
    listeners:
      - flow_type: netflow9
        port: 2055

network_path:
  connections_monitoring:
    enabled: true
  collector:
    workers: 4
DD_EOF

# ── system-probe.yaml ───────────────────────────────────────
cat > "$LAB_DIR/system-probe.yaml" << SP_EOF
traceroute:
  enabled: true
network_config:
  enabled: true
SP_EOF

# ── SNMP profile: seed the custom-profile dir with cisco-csr1000v ──
# The core SNMP loader doesn't ship a compiled-in cisco-csr1000v profile
# (sysObjectID 1.3.6.1.4.1.9.1.1537), and the Python loader hits an
# asyncio "no current event loop in thread Dummy-N" bug when it runs
# more than ~3 instances concurrently. Solution: copy the CSR1000v
# profile + its transitive deps from the embedded Python package into
# the user profile dir so the core loader can resolve it on disk.
# Done at deploy-time (via the dd-agent clab exec hook); we don't write
# the YAML content here — we just rely on the files already on disk.
mkdir -p "$LAB_DIR/conf.d/snmp.d/profiles"
cat > "$LAB_DIR/scripts/install-csr1000v-profile.sh" << 'PROFEOF'
#!/bin/bash
# install-csr1000v-profile.sh — Populate /opt/ddlab/conf.d/snmp.d/profiles/
# with the cisco-csr1000v profile + deps so the agent's core SNMP loader
# can resolve "profile: cisco-csr1000v".
#
# Works pre- OR post-deploy:
#  - Pre-deploy (agent container not yet running): extract profiles from
#    the agent Docker image using a throwaway container. After this, a
#    subsequent `containerlab deploy` brings the agent up with the
#    profile files already visible — no restart needed.
#  - Post-deploy (agent already running and stuck with "unknown profile"):
#    refresh files via docker exec, then docker restart the agent.
#    Callers MUST re-do `containerlab destroy && deploy` afterwards to
#    reattach eth2 (which docker restart drops).
set -e
DST=/opt/ddlab/conf.d/snmp.d/profiles
AGENT_IMAGE="gcr.io/datadoghq/agent:latest"
AGENT=$(docker ps --filter 'name=-dd-agent' --format '{{.Names}}' | head -1 || true)

# Always start with a clean, empty profile dir (avoids sysobjectid
# conflicts between user files and bundled ones — e.g. palo-alto vs
# paloalto-panos that were a pain earlier).
mkdir -p "$DST"
rm -f "$DST/"*.yaml

# Extract bundled profiles from the agent image (works whether or not
# the agent container is currently running).
if [ -n "$AGENT" ] && docker exec "$AGENT" true 2>/dev/null; then
  EXTRACT="docker exec $AGENT"
  echo "[install-csr1000v-profile] Extracting profiles from running agent: $AGENT"
  $EXTRACT bash -c "
    SRC=/opt/datadog-agent/embedded/lib/python3.13/site-packages/datadog_checks/snmp/data/default_profiles
    tar -C \$SRC -czf /tmp/profiles.tgz \
        cisco-csr1000v.yaml _base.yaml _base_cisco.yaml _cisco-generic.yaml \
        _cisco-metadata.yaml _cisco-cpu-memory.yaml \
        \$(cd \$SRC && ls _generic-*.yaml _std-*.yaml 2>/dev/null)
  "
  docker cp "$AGENT:/tmp/profiles.tgz" /tmp/profiles.tgz
else
  echo "[install-csr1000v-profile] Agent not running — extracting profiles from image $AGENT_IMAGE"
  docker pull -q "$AGENT_IMAGE" >/dev/null
  TMP_CID=$(docker create "$AGENT_IMAGE")
  docker cp "$TMP_CID:/opt/datadog-agent/embedded/lib/python3.13/site-packages/datadog_checks/snmp/data/default_profiles" /tmp/default_profiles
  docker rm "$TMP_CID" >/dev/null
  tar -C /tmp/default_profiles -czf /tmp/profiles.tgz \
      cisco-csr1000v.yaml _base.yaml _base_cisco.yaml _cisco-generic.yaml \
      _cisco-metadata.yaml _cisco-cpu-memory.yaml \
      $(cd /tmp/default_profiles && ls _generic-*.yaml _std-*.yaml 2>/dev/null) \
      2>/dev/null || true
  rm -rf /tmp/default_profiles
fi

tar -C "$DST" -xzf /tmp/profiles.tgz
rm -f /tmp/profiles.tgz

# Remove any file that conflicts with embedded-in-image profiles at runtime.
rm -f "$DST/_cisco-voice.yaml" "$DST/_cisco-wlc.yaml" 2>/dev/null || true

echo "[install-csr1000v-profile] Profile dir now contains:"
ls "$DST" | head

# If an agent is running and reported "unknown profile" before we got
# here, its in-memory profile cache is stale. Restart so it rereads the
# user dir on next init. (If it was already OK, the SIGHUP below is a
# no-op and eth2 stays intact.)
if [ -n "$AGENT" ] && docker exec "$AGENT" agent status 2>/dev/null \
      | grep -q 'unknown profile "cisco-csr1000v"'; then
  echo "[install-csr1000v-profile] Agent was stuck with 'unknown profile' — restarting..."
  docker restart "$AGENT" >/dev/null
  echo "[install-csr1000v-profile] WARNING: docker restart dropped clab-managed"
  echo "  eth2 veth. Caller should re-run 'containerlab destroy && deploy'."
elif [ -n "$AGENT" ]; then
  echo "[install-csr1000v-profile] Agent healthy — SIGHUP reload."
  docker kill -s HUP "$AGENT" >/dev/null 2>&1 || true
fi
echo "[OK] cisco-csr1000v profile installed."
PROFEOF
chmod +x "$LAB_DIR/scripts/install-csr1000v-profile.sh"

# ── SNMP instances.yaml ─────────────────────────────────────
# Static instances with explicit "loader: core" + "profile: cisco-csr1000v".
# Requires the profile files to be installed in the user profile dir
# (see install-csr1000v-profile.sh) so the core loader can resolve it.
cat > "$LAB_DIR/conf.d/snmp.d/instances.yaml" << SNMP_EOF
instances:

  # ── CSR1 — Bangkok DC1 Edge (eBGP) ────────────────────────
  - ip_address: $CSR_MGMT_IP
    snmp_version: 3
    user: $SNMP_V3_USER
    authProtocol: sha
    authKey: $SNMP_V3_AUTH_PASS
    privProtocol: aes
    privKey: $SNMP_V3_PRIV_PASS
    loader: core
    profile: cisco-csr1000v
    tags:
      - "device_type:router"
      - "vendor:cisco"
      - "site:$${GEO_BKK_LABEL}"
      - "geolocation:bkk-dc1"
      - "role:bgp-edge"
      - "hop:1"

  # ── CSR2 — WAN Transit (iBGP) ─────────────────────────────
  - ip_address: $CSR2_MGMT_IP
    snmp_version: 3
    user: $SNMP_V3_USER
    authProtocol: sha
    authKey: $SNMP_V3_AUTH_PASS
    privProtocol: aes
    privKey: $SNMP_V3_PRIV_PASS
    loader: core
    profile: cisco-csr1000v
    tags:
      - "device_type:router"
      - "vendor:cisco"
      - "site:wan-transit"
      - "geolocation:wan-transit"
      - "role:wan-transit"
      - "hop:2"

  # ── CSR3 — Chiang Mai DC2 Edge (iBGP) ─────────────────────
  - ip_address: $CSR3_MGMT_IP
    snmp_version: 3
    user: $SNMP_V3_USER
    authProtocol: sha
    authKey: $SNMP_V3_AUTH_PASS
    privProtocol: aes
    privKey: $SNMP_V3_PRIV_PASS
    loader: core
    profile: cisco-csr1000v
    tags:
      - "device_type:router"
      - "vendor:cisco"
      - "site:$${GEO_CNX_LABEL}"
      - "geolocation:cnx-dc2"
      - "role:dc-edge"
      - "hop:3"

  # ── CSR4 — Chiang Mai DC2 Access (iBGP) ───────────────────
  - ip_address: $CSR4_MGMT_IP
    snmp_version: 3
    user: $SNMP_V3_USER
    authProtocol: sha
    authKey: $SNMP_V3_AUTH_PASS
    privProtocol: aes
    privKey: $SNMP_V3_PRIV_PASS
    loader: core
    profile: cisco-csr1000v
    tags:
      - "device_type:router"
      - "vendor:cisco"
      - "site:$${GEO_CNX_LABEL}"
      - "geolocation:cnx-dc2-access"
      - "role:dc-access"
      - "hop:4"

  # ── CSR5 — Chiang Mai DC2 Endpoint (iBGP) ─────────────────
  - ip_address: $CSR5_MGMT_IP
    snmp_version: 3
    user: $SNMP_V3_USER
    authProtocol: sha
    authKey: $SNMP_V3_AUTH_PASS
    privProtocol: aes
    privKey: $SNMP_V3_PRIV_PASS
    loader: core
    profile: cisco-csr1000v
    tags:
      - "device_type:router"
      - "vendor:cisco"
      - "site:$${GEO_CNX_LABEL}"
      - "geolocation:cnx-dc2-access"
      - "role:dc-endpoint"
      - "hop:5"
SNMP_EOF

# ── SNMP custom profiles ────────────────────────────────────
# NOTE: we do NOT write custom profiles to /etc/datadog-agent/conf.d/snmp.d/
# profiles/ anymore — the agent's Python SNMP check auto-loads its full
# bundled profile set (cisco-csr1000v, palo-alto, f5-big-ip, …) from the
# embedded datadog_checks.snmp package. Adding overlapping custom profiles
# here causes "ConfigurationError: Profile X has the same sysObjectID as Y"
# and breaks the check constructor, so we keep the user dir empty and let
# the bundled profiles do their job. The code below is retained (commented)
# only in case you want to re-enable a CSR BGP-MIB custom profile later.
: <<'DISABLED_CUSTOM_PROFILES'
cat > "$LAB_DIR/conf.d/snmp.d/profiles/cisco-csr-bgp.yaml" << BGPPROF_EOF
extends:
  - _base.yaml
  - _generic-if.yaml
  - cisco-routers.yaml

metrics:
  - MIB: BGP4-MIB
    table:
      name: bgpPeerTable
      OID: 1.3.6.1.2.1.15.3
    symbols:
      - OID: 1.3.6.1.2.1.15.3.1.2
        name: bgpPeerState
      - OID: 1.3.6.1.2.1.15.3.1.24
        name: bgpPeerFsmEstablishedTime
      - OID: 1.3.6.1.2.1.15.3.1.12
        name: bgpPeerInUpdates
      - OID: 1.3.6.1.2.1.15.3.1.13
        name: bgpPeerOutUpdates
    metric_tags:
      - column:
          OID: 1.3.6.1.2.1.15.3.1.7
          name: bgpPeerRemoteAddr
        tag: bgp_peer
      - column:
          OID: 1.3.6.1.2.1.15.3.1.9
          name: bgpPeerRemoteAs
        tag: bgp_peer_as
BGPPROF_EOF

cat > "$LAB_DIR/conf.d/snmp.d/profiles/f5-bigip-ltm.yaml" << F5PROF_EOF
extends:
  - _base.yaml
  - f5-big-ip.yaml

metrics:
  - MIB: F5-BIGIP-LOCAL-MIB
    table:
      name: ltmVirtualServStatTable
      OID: 1.3.6.1.4.1.3375.2.2.10.2.3
    symbols:
      - OID: 1.3.6.1.4.1.3375.2.2.10.2.3.1.5
        name: ltmVirtualServStatClientCurConns
      - OID: 1.3.6.1.4.1.3375.2.2.10.2.3.1.7
        name: ltmVirtualServStatClientTotConns
    metric_tags:
      - column:
          OID: 1.3.6.1.4.1.3375.2.2.10.2.3.1.1
          name: ltmVirtualServStatName
        tag: virtual_server
  - MIB: F5-BIGIP-LOCAL-MIB
    table:
      name: ltmPoolMbrStatusTable
      OID: 1.3.6.1.4.1.3375.2.2.5.6.2
    symbols:
      - OID: 1.3.6.1.4.1.3375.2.2.5.6.2.1.5
        name: ltmPoolMbrStatusAvailState
    metric_tags:
      - column:
          OID: 1.3.6.1.4.1.3375.2.2.5.6.2.1.1
          name: ltmPoolMbrStatusPoolName
        tag: pool_name
      - column:
          OID: 1.3.6.1.4.1.3375.2.2.5.6.2.1.3
          name: ltmPoolMbrStatusAddr
        tag: member_addr
  - MIB: F5-BIGIP-SYSTEM-MIB
    symbol:
      OID: 1.3.6.1.4.1.3375.2.1.14.1.1.0
      name: sysCmFailoverStatusId
F5PROF_EOF

cat > "$LAB_DIR/conf.d/snmp.d/profiles/paloalto-panos.yaml" << PANPROF_EOF
extends:
  - _base.yaml
  - _generic-if.yaml

sysobjectid:
  - 1.3.6.1.4.1.25461.2.3.*

metrics:
  - MIB: PAN-COMMON-MIB
    symbol:
      OID: 1.3.6.1.4.1.25461.2.1.2.3.3.0
      name: panSessionActive
  - MIB: PAN-COMMON-MIB
    symbol:
      OID: 1.3.6.1.4.1.25461.2.1.2.3.2.0
      name: panSessionMax
  - MIB: PAN-COMMON-MIB
    symbol:
      OID: 1.3.6.1.4.1.25461.2.1.2.3.5.0
      name: panThroughput
  - MIB: PAN-COMMON-MIB
    symbol:
      OID: 1.3.6.1.4.1.25461.2.1.2.1.10.0
      name: panSysHAState
PANPROF_EOF
DISABLED_CUSTOM_PROFILES
# Ensure the user profile dir stays empty (purge any stale custom files
# from previous revisions of this template).
rm -f "$LAB_DIR/conf.d/snmp.d/profiles/"*.yaml 2>/dev/null || true

# ── Network Path targets ─────────────────────────────────────
# Two categories of targets:
#   (a) Mgmt-plane targets (.10/.11/.12) — 1 hop each via clab-mgmt bridge.
#       Useful as a control / baseline for management-plane reachability.
#   (b) Data-plane loopback targets (10.100.1.1 / .2.1 / .3.1) — traverse
#       the data-plane chain dd-agent(eth2) -> CSR1 Gi4 -> CSR1 Gi3 ->
#       CSR2 Gi2 -> CSR2 Gi3 -> CSR3 Gi2. These produce real multi-hop
#       traceroute output in NetworkPath (1, 2, and 3 router hops).
cat > "$LAB_DIR/conf.d/network_path.d/conf.yaml" << NP_EOF
# ── Display names ────────────────────────────────────────────
# Each instance uses a friendly hostname (resolved via /etc/hosts that
# the dd-agent container populates at clab deploy) so the Datadog
# NetworkPath UI's "Destination" column shows a readable name. The
# "destination_service" field additionally groups the path in the
# Service column of the UI and can be used to filter/build dashboards.
instances:
  # ── (a) Mgmt-plane baseline — BKK edge ──────────────────────
  - hostname: csr1-bkk-edge-mgmt
    protocol: TCP
    port: 22
    source_service: dd-lab-agent
    destination_service: CSR1-BKK-EDGE (mgmt)
    tags:
      - "path_name:agent-to-csr1-mgmt"
      - "destination_role:bgp-edge"
      - "geolocation:bkk-dc1"
      - "path_type:mgmt"
      - "expected_hops:1"
    max_ttl: 5
    traceroute_queries: 3
    min_collection_interval: 60

  # ── (a) Mgmt-plane baseline — WAN Transit ───────────────────
  - hostname: csr2-wan-transit-mgmt
    protocol: TCP
    port: 22
    source_service: dd-lab-agent
    destination_service: CSR2-WAN-TRANSIT (mgmt)
    tags:
      - "path_name:agent-to-csr2-mgmt"
      - "destination_role:wan-transit"
      - "geolocation:wan-transit"
      - "path_type:mgmt"
      - "expected_hops:1"
    max_ttl: 5
    traceroute_queries: 3
    min_collection_interval: 60

  # ── (a) Mgmt-plane baseline — CNX edge ──────────────────────
  - hostname: csr3-cnx-edge-mgmt
    protocol: TCP
    port: 22
    source_service: dd-lab-agent
    destination_service: CSR3-CNX-DC-EDGE (mgmt)
    tags:
      - "path_name:agent-to-csr3-mgmt"
      - "destination_role:dc-edge"
      - "geolocation:cnx-dc2"
      - "path_type:mgmt"
      - "expected_hops:1"
    max_ttl: 5
    traceroute_queries: 3
    min_collection_interval: 60

  # ── (b) Data-plane: CSR1 loopback (1 router hop) ────────────
  - hostname: csr1-bkk-edge
    protocol: ICMP
    source_service: dd-lab-agent
    destination_service: CSR1-BKK-EDGE (loopback)
    tags:
      - "path_name:agent-to-bkk-edge"
      - "destination_role:bgp-edge"
      - "geolocation:bkk-dc1"
      - "path_type:data-plane"
      - "expected_hops:1"
    max_ttl: 10
    traceroute_queries: 3
    min_collection_interval: 60

  # ── (b) Data-plane: CSR2 loopback (BKK -> Transit) ──────────
  - hostname: csr2-wan-transit
    protocol: ICMP
    source_service: dd-lab-agent
    destination_service: CSR2-WAN-TRANSIT (loopback)
    tags:
      - "path_name:agent-to-wan-transit"
      - "destination_role:wan-transit"
      - "geolocation:wan-transit"
      - "path_type:data-plane"
      - "expected_hops:2"
    max_ttl: 10
    traceroute_queries: 3
    min_collection_interval: 60

  # ── (b) Data-plane: CSR3 loopback (BKK -> Transit -> CNX) ───
  - hostname: csr3-cnx-edge
    protocol: ICMP
    source_service: dd-lab-agent
    destination_service: CSR3-CNX-DC-EDGE (loopback)
    tags:
      - "path_name:agent-to-cnx-edge"
      - "destination_role:dc-edge"
      - "geolocation:cnx-dc2"
      - "path_type:data-plane"
      - "expected_hops:3"
    max_ttl: 10
    traceroute_queries: 3
    min_collection_interval: 60

  # ── (b) Data-plane: CSR4 loopback (4 hops: CSR1->2->3->4) ────
  - hostname: csr4-cnx-access
    protocol: ICMP
    source_service: dd-lab-agent
    destination_service: CSR4-CNX-ACCESS (loopback)
    tags:
      - "path_name:agent-to-csr4"
      - "destination_role:dc-access"
      - "geolocation:cnx-dc2-access"
      - "path_type:data-plane"
      - "expected_hops:4"
    max_ttl: 12
    traceroute_queries: 3
    min_collection_interval: 60

  # ── (b) Data-plane: CSR5 loopback (5 hops, end of chain) ─────
  - hostname: csr5-cnx-endpoint
    protocol: ICMP
    source_service: dd-lab-agent
    destination_service: CSR5-CNX-ENDPOINT (loopback)
    tags:
      - "path_name:agent-to-csr5"
      - "destination_role:dc-endpoint"
      - "geolocation:cnx-dc2-access"
      - "path_type:data-plane"
      - "expected_hops:5"
    max_ttl: 12
    traceroute_queries: 3
    min_collection_interval: 60
NP_EOF

echo "[$(date)] Datadog Agent configs written."

# ============================================================
# STAGE 8 — Render Device Config Files
# ============================================================
echo "[$(date)] STAGE 8: Rendering device startup configs..."

# ── CSR1 startup config — Bangkok DC1 Edge ──────────────────
# eBGP to FRR (AS $BGP_PEER_AS), iBGP to CSR2 (10.0.12.2)
cat > "$LAB_DIR/configs/csr-startup.cfg" << CSR1_EOF
hostname CSR-BKK-EDGE
!
ip domain-name lab.local
!
ip access-list standard ACL-SNMP
 permit $AGENT_MGMT_IP
!
snmp-server view ViewAll iso included
snmp-server group DDGroup v3 priv read ViewAll access ACL-SNMP
snmp-server user $SNMP_V3_USER DDGroup v3 auth sha $SNMP_V3_AUTH_PASS priv aes 128 $SNMP_V3_PRIV_PASS
snmp-server community $SNMP_COMMUNITY RO ACL-SNMP
snmp-server location Bangkok-DC1-Core
snmp-server contact noc@lab.local
snmp-server enable traps bgp
snmp-server enable traps snmp linkdown linkup
snmp-server host $AGENT_MGMT_IP version 3 priv $SNMP_V3_USER
!
cdp run
!
! ── Loopback0 — advertised via iBGP ─────────────────────────
interface Loopback0
 ip address 10.100.1.1 255.255.255.255
!
! ── Gi2 — eBGP link to FRR (172.16.0.0/30) ─────────────────
interface GigabitEthernet2
 description TO-FRR-BGP-PEER
 ip address 172.16.0.2 255.255.255.252
 cdp enable
 no shutdown
!
! ── Gi3 — iBGP link to CSR2 (10.0.12.0/30) ─────────────────
interface GigabitEthernet3
 description TO-CSR2
 ip address 10.0.12.1 255.255.255.252
 cdp enable
 no shutdown
!
! ── Gi4 — Data-plane uplink to dd-agent (10.99.0.0/30) ─────
! Entry point for NetworkPath multi-hop traffic from the agent.
! Must be in the GLOBAL routing table (not the Mgmt-intf VRF).
interface GigabitEthernet4
 description TO-DD-AGENT-DATA-PLANE
 ip address 10.99.0.1 255.255.255.252
 cdp enable
 no shutdown
!
! ── Static routes — make the entire CSR + Linux-hop chain
!    reachable even if iBGP is still converging at boot ──────
ip route 10.100.2.1 255.255.255.255 10.0.12.2
ip route 10.100.3.1 255.255.255.255 10.0.12.2
ip route 10.100.4.1 255.255.255.255 10.0.12.2
ip route 10.100.5.1 255.255.255.255 10.0.12.2
ip route 10.0.23.0 255.255.255.252 10.0.12.2
ip route 10.0.34.0 255.255.255.252 10.0.12.2
ip route 10.0.45.0 255.255.255.252 10.0.12.2
!
! ── BGP: eBGP to FRR + iBGP to CSR2. Advertise local networks
!    so CSR2 / CSR3 know how to reach 10.99.0.0/30 (agent path)
!    on the return trip. ───────────────────────────────────────
router bgp $BGP_LOCAL_AS
 bgp router-id 10.100.1.1
 neighbor 172.16.0.1 remote-as $BGP_PEER_AS
 neighbor 172.16.0.1 description FRR-Internet-Sim
 neighbor 10.0.12.2 remote-as $BGP_LOCAL_AS
 neighbor 10.0.12.2 description iBGP-to-CSR2
 address-family ipv4
  network 10.99.0.0 mask 255.255.255.252
  network 10.100.1.1 mask 255.255.255.255
  neighbor 172.16.0.1 activate
  neighbor 10.0.12.2 activate
  neighbor 10.0.12.2 next-hop-self
!
end
CSR1_EOF

# ── CSR2 startup config — WAN Transit ───────────────────────
# iBGP with CSR1 (10.0.12.1) and CSR3 (10.0.23.2)
cat > "$LAB_DIR/configs/csr2-startup.cfg" << CSR2_EOF
hostname CSR-WAN-TRANSIT
!
ip domain-name lab.local
!
ip access-list standard ACL-SNMP
 permit $AGENT_MGMT_IP
!
snmp-server view ViewAll iso included
snmp-server group DDGroup v3 priv read ViewAll access ACL-SNMP
snmp-server user $SNMP_V3_USER DDGroup v3 auth sha $SNMP_V3_AUTH_PASS priv aes 128 $SNMP_V3_PRIV_PASS
snmp-server community $SNMP_COMMUNITY RO ACL-SNMP
snmp-server location WAN-Transit-Core
snmp-server contact noc@lab.local
snmp-server enable traps bgp
snmp-server enable traps snmp linkdown linkup
snmp-server host $AGENT_MGMT_IP version 3 priv $SNMP_V3_USER
!
cdp run
!
interface Loopback0
 ip address 10.100.2.1 255.255.255.255
!
interface GigabitEthernet2
 description TO-CSR1
 ip address 10.0.12.2 255.255.255.252
 cdp enable
 no shutdown
!
interface GigabitEthernet3
 description TO-CSR3
 ip address 10.0.23.1 255.255.255.252
 cdp enable
 no shutdown
!
! ── Static routes toward the downstream Linux hops (4 + 5) ──
ip route 10.100.4.1 255.255.255.255 10.0.23.2
ip route 10.100.5.1 255.255.255.255 10.0.23.2
ip route 10.0.34.0 255.255.255.252 10.0.23.2
ip route 10.0.45.0 255.255.255.252 10.0.23.2
!
router bgp $BGP_LOCAL_AS
 bgp router-id 10.100.2.1
 neighbor 10.0.12.1 remote-as $BGP_LOCAL_AS
 neighbor 10.0.12.1 description iBGP-to-CSR1
 neighbor 10.0.23.2 remote-as $BGP_LOCAL_AS
 neighbor 10.0.23.2 description iBGP-to-CSR3
 address-family ipv4
  network 10.100.2.1 mask 255.255.255.255
  neighbor 10.0.12.1 activate
  neighbor 10.0.12.1 next-hop-self
  neighbor 10.0.23.2 activate
  neighbor 10.0.23.2 next-hop-self
!
end
CSR2_EOF

# ── CSR3 startup config — Chiang Mai DC2 Edge ───────────────
# iBGP with CSR2 (10.0.23.1)
cat > "$LAB_DIR/configs/csr3-startup.cfg" << CSR3_EOF
hostname CSR-CNX-DC-EDGE
!
ip domain-name lab.local
!
ip access-list standard ACL-SNMP
 permit $AGENT_MGMT_IP
!
snmp-server view ViewAll iso included
snmp-server group DDGroup v3 priv read ViewAll access ACL-SNMP
snmp-server user $SNMP_V3_USER DDGroup v3 auth sha $SNMP_V3_AUTH_PASS priv aes 128 $SNMP_V3_PRIV_PASS
snmp-server community $SNMP_COMMUNITY RO ACL-SNMP
snmp-server location ChiangMai-DC2-Edge
snmp-server contact noc@lab.local
snmp-server enable traps bgp
snmp-server enable traps snmp linkdown linkup
snmp-server host $AGENT_MGMT_IP version 3 priv $SNMP_V3_USER
!
cdp run
!
interface Loopback0
 ip address 10.100.3.1 255.255.255.255
!
interface GigabitEthernet2
 description TO-CSR2
 ip address 10.0.23.2 255.255.255.252
 cdp enable
 no shutdown
!
! ── Gi3 — chain extension toward CSR4 ────────────────────────
interface GigabitEthernet3
 description TO-CSR4
 ip address 10.0.34.1 255.255.255.252
 cdp enable
 no shutdown
!
! Default back to CSR2 for non-local destinations
ip route 0.0.0.0 0.0.0.0 10.0.23.1
! Static fallback for downstream CSR4/CSR5 (resilient to slow iBGP)
ip route 10.0.45.0 255.255.255.252 10.0.34.2
ip route 10.100.4.1 255.255.255.255 10.0.34.2
ip route 10.100.5.1 255.255.255.255 10.0.34.2
!
router bgp $BGP_LOCAL_AS
 bgp router-id 10.100.3.1
 neighbor 10.0.23.1 remote-as $BGP_LOCAL_AS
 neighbor 10.0.23.1 description iBGP-to-CSR2
 neighbor 10.0.34.2 remote-as $BGP_LOCAL_AS
 neighbor 10.0.34.2 description iBGP-to-CSR4
 address-family ipv4
  network 10.100.3.1 mask 255.255.255.255
  neighbor 10.0.23.1 activate
  neighbor 10.0.23.1 next-hop-self
  neighbor 10.0.34.2 activate
  neighbor 10.0.34.2 next-hop-self
!
end
CSR3_EOF

# ── CSR4 startup config — Chiang Mai DC2 Access ─────────────
# iBGP with CSR3 (10.0.34.1) and CSR5 (10.0.45.2)
cat > "$LAB_DIR/configs/csr4-startup.cfg" << CSR4_EOF
hostname CSR-CNX-ACCESS
!
ip domain-name lab.local
!
ip access-list standard ACL-SNMP
 permit $AGENT_MGMT_IP
!
snmp-server view ViewAll iso included
snmp-server group DDGroup v3 priv read ViewAll access ACL-SNMP
snmp-server user $SNMP_V3_USER DDGroup v3 auth sha $SNMP_V3_AUTH_PASS priv aes 128 $SNMP_V3_PRIV_PASS
snmp-server community $SNMP_COMMUNITY RO ACL-SNMP
snmp-server location ChiangMai-DC2-Access
snmp-server contact noc@lab.local
snmp-server enable traps bgp
snmp-server enable traps snmp linkdown linkup
snmp-server host $AGENT_MGMT_IP version 3 priv $SNMP_V3_USER
!
cdp run
!
interface Loopback0
 ip address 10.100.4.1 255.255.255.255
!
interface GigabitEthernet2
 description TO-CSR3
 ip address 10.0.34.2 255.255.255.252
 cdp enable
 no shutdown
!
interface GigabitEthernet3
 description TO-CSR5
 ip address 10.0.45.1 255.255.255.252
 cdp enable
 no shutdown
!
ip route 0.0.0.0 0.0.0.0 10.0.34.1
! Static fallback: reach CSR5 loopback + upstream CSR1/2/3 loopbacks
ip route 10.100.5.1 255.255.255.255 10.0.45.2
ip route 10.100.1.1 255.255.255.255 10.0.34.1
ip route 10.100.2.1 255.255.255.255 10.0.34.1
ip route 10.100.3.1 255.255.255.255 10.0.34.1
ip route 10.99.0.0 255.255.255.252 10.0.34.1
!
router bgp $BGP_LOCAL_AS
 bgp router-id 10.100.4.1
 neighbor 10.0.34.1 remote-as $BGP_LOCAL_AS
 neighbor 10.0.34.1 description iBGP-to-CSR3
 neighbor 10.0.45.2 remote-as $BGP_LOCAL_AS
 neighbor 10.0.45.2 description iBGP-to-CSR5
 address-family ipv4
  network 10.100.4.1 mask 255.255.255.255
  neighbor 10.0.34.1 activate
  neighbor 10.0.34.1 next-hop-self
  neighbor 10.0.45.2 activate
  neighbor 10.0.45.2 next-hop-self
!
end
CSR4_EOF

# ── CSR5 startup config — Chiang Mai DC2 Endpoint ───────────
# iBGP with CSR4 (10.0.45.1)
cat > "$LAB_DIR/configs/csr5-startup.cfg" << CSR5_EOF
hostname CSR-CNX-ENDPOINT
!
ip domain-name lab.local
!
ip access-list standard ACL-SNMP
 permit $AGENT_MGMT_IP
!
snmp-server view ViewAll iso included
snmp-server group DDGroup v3 priv read ViewAll access ACL-SNMP
snmp-server user $SNMP_V3_USER DDGroup v3 auth sha $SNMP_V3_AUTH_PASS priv aes 128 $SNMP_V3_PRIV_PASS
snmp-server community $SNMP_COMMUNITY RO ACL-SNMP
snmp-server location ChiangMai-DC2-Endpoint
snmp-server contact noc@lab.local
snmp-server enable traps bgp
snmp-server enable traps snmp linkdown linkup
snmp-server host $AGENT_MGMT_IP version 3 priv $SNMP_V3_USER
!
cdp run
!
interface Loopback0
 ip address 10.100.5.1 255.255.255.255
!
interface GigabitEthernet2
 description TO-CSR4
 ip address 10.0.45.2 255.255.255.252
 cdp enable
 no shutdown
!
ip route 0.0.0.0 0.0.0.0 10.0.45.1
! Static fallback to upstream chain
ip route 10.99.0.0 255.255.255.252 10.0.45.1
ip route 10.100.1.1 255.255.255.255 10.0.45.1
ip route 10.100.2.1 255.255.255.255 10.0.45.1
ip route 10.100.3.1 255.255.255.255 10.0.45.1
ip route 10.100.4.1 255.255.255.255 10.0.45.1
!
router bgp $BGP_LOCAL_AS
 bgp router-id 10.100.5.1
 neighbor 10.0.45.1 remote-as $BGP_LOCAL_AS
 neighbor 10.0.45.1 description iBGP-to-CSR4
 address-family ipv4
  network 10.100.5.1 mask 255.255.255.255
  neighbor 10.0.45.1 activate
  neighbor 10.0.45.1 next-hop-self
!
end
CSR5_EOF

# ── FRR BGP peer config (Internet simulation) ───────────────
cat > "$LAB_DIR/configs/frr.conf" << FRR_EOF
frr version 8.0
frr defaults traditional
hostname bgp-internet-sim
!
interface eth1
 ip address 172.16.0.1/30
!
router bgp $BGP_PEER_AS
 bgp router-id 172.16.0.1
 neighbor 172.16.0.2 remote-as $BGP_LOCAL_AS
 neighbor 172.16.0.2 description CSR-BKK-EDGE
 !
 address-family ipv4 unicast
  neighbor 172.16.0.2 activate
  network 0.0.0.0/0
 exit-address-family
!
line vty
!
FRR_EOF

echo "[$(date)] Device config files written."

# ============================================================
# STAGE 9 — System Tuning
# ============================================================
echo "[$(date)] STAGE 9: System tuning..."

# IP forwarding for container routing
cat >> /etc/sysctl.conf << SYSCTL_EOF
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
SYSCTL_EOF
sysctl -p

# Allow SNMP trap port 162 binding without root for Datadog Agent
# This runs after Agent is started by the deploy script
cat > /etc/rc.local << 'RCLOCAL_EOF'
#!/bin/bash
# Re-apply setcap after Agent upgrades (port 162 < 1024 requires cap)
AGENT_BIN=$(find /opt/datadog-packages -name agent -type f 2>/dev/null | head -1)
if [ -n "$AGENT_BIN" ]; then
  setcap cap_net_bind_service=+ep "$AGENT_BIN"
fi
exit 0
RCLOCAL_EOF
chmod +x /etc/rc.local

# ============================================================
# STAGE 10 — Copy Lab Scripts to /opt/ddlab/scripts/
# ============================================================
echo "[$(date)] STAGE 10: Writing lab automation scripts..."

# We'll write these inline so they're rendered with credentials
# ── build-images.sh: build all 3 vrnetlab images ────────────
cat > "$LAB_DIR/scripts/build-images.sh" << 'BLDEOF'
#!/bin/bash
# build-images.sh — Build vrnetlab VM container images
# Place your .qcow2 files in /opt/vrnetlab/<type>/ first
set -euo pipefail
LOG=/var/log/ddlab-build-images.log
exec > >(tee -a "$LOG") 2>&1
echo "[$(date)] Building vrnetlab images..."

VRNL=/opt/vrnetlab

build_image() {
  local name="$1"
  local dir="$2"
  local qcow_pattern="$3"
  echo "--- Building $name ---"
  if ls "$dir"/$qcow_pattern 1>/dev/null 2>&1; then
    cd "$dir" && make
    echo "[OK] $name image built."
  else
    echo "[SKIP] No $qcow_pattern found in $dir — copy the qcow2 image there first."
  fi
}

build_image "Cisco CSR1000v" "$VRNL/csr"      "*.qcow2"
# F5/PAN removed from topology — their vrnetlab builds are skipped.
# (leave build_image calls commented for future reference)
# build_image "F5 BIG-IP VE"   "$VRNL/f5_bigip" "BIGIP-*.qcow2"
# build_image "Palo Alto PA-VM" "$VRNL/pan"      "PA-VM-KVM-*.qcow2"

# ── Cache the built image to GCS so future apply cycles skip the build ──
CACHE_BUCKET='${image_cache_bucket}'
CSR_IMAGE_TAG='${csr_image_tag}'
if [ -n "$CACHE_BUCKET" ] && docker image inspect "$CSR_IMAGE_TAG" >/dev/null 2>&1; then
  echo "[$(date)] Exporting $CSR_IMAGE_TAG to gs://$CACHE_BUCKET/vrnetlab-cisco_csr1000v.tar.gz ..."
  docker save "$CSR_IMAGE_TAG" | gzip -1 > /tmp/csr-image.tar.gz
  gsutil cp /tmp/csr-image.tar.gz "gs://$CACHE_BUCKET/vrnetlab-cisco_csr1000v.tar.gz"
  rm -f /tmp/csr-image.tar.gz
  echo "[OK] Image cached. Next terraform destroy+apply will skip rebuild."
fi

echo "[$(date)] Image build complete. Run 'docker images | grep vrnetlab' to verify."
BLDEOF
chmod +x "$LAB_DIR/scripts/build-images.sh"

# ── deploy-lab.sh ───────────────────────────────────────────
cat > "$LAB_DIR/scripts/deploy-lab.sh" << DEPEOF
#!/bin/bash
# deploy-lab.sh — Deploy Containerlab topology and wait for VMs to boot
set -euo pipefail
TOPO=/opt/ddlab/containerlab/ndm-lab.clab.yml
LOG=/var/log/ddlab-deploy.log
exec > >(tee -a "\$LOG") 2>&1

# Pre-seed SNMP profile BEFORE the agent container starts, so the core
# loader sees cisco-csr1000v on disk at init time — avoids the restart
# dance that would drop eth2.
echo "[$(date)] Pre-seeding cisco-csr1000v SNMP profile..."
bash /opt/ddlab/scripts/install-csr1000v-profile.sh || true

# Idempotency check: we must look at RUNNING docker containers, not
# just the clab state file. On a fresh VM with a persisted boot disk,
# /opt/ddlab/containerlab/clab-${lab_name}/topology-data.json can survive
# even though the containers were destroyed — that would fool
# `containerlab inspect` into thinking the lab is already up.
RUNNING_CSRS=\$(sudo docker ps --format '{{.Names}}' | grep -c "^clab-${lab_name}-csr" || true)
if [ "\$RUNNING_CSRS" -ge 5 ]; then
  echo "[$(date)] Lab already deployed (\$RUNNING_CSRS CSR containers running) — skipping containerlab deploy."
  echo "  (To force a fresh deploy, run: sudo containerlab destroy --topo \$TOPO --cleanup)"
else
  # Containers aren't running. Clean up any stale clab state before deploy
  # so containerlab doesn't refuse with "lab already deployed".
  if [ -d "/opt/ddlab/containerlab/clab-${lab_name}" ]; then
    echo "[$(date)] Cleaning stale containerlab state (no running CSRs found)..."
    sudo containerlab destroy --topo "\$TOPO" --cleanup 2>/dev/null || true
    sudo docker ps -a --filter "label=containerlab=${lab_name}" -q | xargs -r sudo docker rm -f 2>/dev/null || true
    sudo rm -rf "/opt/ddlab/containerlab/clab-${lab_name}"
  fi
  echo "[$(date)] Deploying Containerlab topology..."
  sudo containerlab deploy --topo "\$TOPO"
fi

echo "[$(date)] Topology deployed. Waiting for CSR1000v VMs to boot..."
echo "  Each Cisco CSR1000v QEMU VM takes ~5-7 min to reach CVAC-4-CONFIG_DONE."
echo "  5 CSRs boot in parallel on a machine with enough vCPUs."
echo "  Monitoring boot status..."

wait_for_boot() {
  local container="\$1"
  local ready_pattern="\$2"
  local timeout=\$${3:-720}
  local elapsed=0
  echo "  Waiting for \$container to boot (max \$${timeout}s)..."
  while [ \$elapsed -lt \$timeout ]; do
    if docker logs "\$container" 2>&1 | grep -q "\$ready_pattern"; then
      echo "  [OK] \$container is ready (\$${elapsed}s)"
      return 0
    fi
    sleep 15
    elapsed=\$((elapsed+15))
    echo "  ... \$container: \$${elapsed}s elapsed"
  done
  echo "  [WARN] \$container did not report ready within \$${timeout}s — check: docker logs \$container"
  return 1
}

wait_for_boot "clab-$${CLAB_NAME}-csr"   "CVAC-4-CONFIG_DONE" 600 || true
wait_for_boot "clab-$${CLAB_NAME}-csr2"  "CVAC-4-CONFIG_DONE" 600 || true
wait_for_boot "clab-$${CLAB_NAME}-csr3"  "CVAC-4-CONFIG_DONE" 600 || true
wait_for_boot "clab-$${CLAB_NAME}-csr4"  "CVAC-4-CONFIG_DONE" 600 || true
wait_for_boot "clab-$${CLAB_NAME}-csr5"  "CVAC-4-CONFIG_DONE" 600 || true

# ── Network Path NAT setup ──────────────────────────────────
# system-probe runs in the HOST network namespace, not the container's.
# We route 10.0.0.0/8 through dd-agent (which has a direct data-plane
# link on eth2 to CSR1 Gi4), and use MASQUERADE so ICMP time-exceeded
# responses from CSR2/CSR3 return cleanly through 10.99.0.1.
echo "[$(date)] Configuring Network Path NAT routing via dd-agent..."
DDPID=\$(docker inspect clab-$${CLAB_NAME}-dd-agent --format '{{.State.Pid}}' 2>/dev/null)
if [ -n "\$DDPID" ] && [ "\$DDPID" != "0" ]; then
  # Enable IP forwarding in dd-agent network namespace
  nsenter -n -t "\$DDPID" -- sysctl -w net.ipv4.ip_forward=1
  # MASQUERADE: packets forwarded out eth2 appear sourced from 10.99.0.1
  nsenter -n -t "\$DDPID" -- iptables -t nat -C POSTROUTING -o eth2 -j MASQUERADE 2>/dev/null || \
    nsenter -n -t "\$DDPID" -- iptables -t nat -A POSTROUTING -o eth2 -j MASQUERADE
  # Route all 10/8 traffic via dd-agent (bypasses SLiRP NAT on CSR1 management)
  ip route del 10.0.0.0/8 2>/dev/null || true
  ip route add 10.0.0.0/8 via 172.20.20.5
  echo "[OK] Host route: 10.0.0.0/8 via 172.20.20.5 (dd-agent), MASQUERADE on eth2"
else
  echo "[WARN] dd-agent container not found — Network Path multi-hop may show 100% loss"
fi

echo "[$(date)] VMs booted."

# (The SNMP profile was already pre-seeded at the top of this script,
# BEFORE containerlab deploy, so the agent's core loader has it cached
# correctly from init. Re-run as a safety net — it's idempotent and on
# a healthy agent reduces to a SIGHUP.)
echo "[$(date)] Verifying cisco-csr1000v SNMP profile..."
bash /opt/ddlab/scripts/install-csr1000v-profile.sh || true

# ── Populate /etc/hosts inside dd-agent (NetworkPath display names)
#    clab exec: is idempotent but can race with container-start; redo here
echo "[$(date)] Ensuring dd-agent /etc/hosts is populated..."
docker exec clab-$${CLAB_NAME}-dd-agent bash -c '
grep -q lab.local /etc/hosts && exit 0
cat >> /etc/hosts <<HOSTS
172.20.20.10 csr1-bkk-edge-mgmt csr-bkk-edge-mgmt.lab.local
172.20.20.11 csr2-wan-transit-mgmt csr-wan-transit-mgmt.lab.local
172.20.20.12 csr3-cnx-edge-mgmt csr-cnx-edge-mgmt.lab.local
172.20.20.14 csr4-cnx-access-mgmt csr-cnx-access-mgmt.lab.local
172.20.20.15 csr5-cnx-endpoint-mgmt csr-cnx-endpoint-mgmt.lab.local
10.100.1.1   csr1-bkk-edge csr-bkk-edge.lab.local
10.100.2.1   csr2-wan-transit csr-wan-transit.lab.local
10.100.3.1   csr3-cnx-edge csr-cnx-edge.lab.local
10.100.4.1   csr4-cnx-access csr-cnx-access.lab.local
10.100.5.1   csr5-cnx-endpoint csr-cnx-endpoint.lab.local
HOSTS'

echo "[$(date)] Deployment complete. Running validation..."
bash /opt/ddlab/scripts/validate.sh || true
DEPEOF
chmod +x "$LAB_DIR/scripts/deploy-lab.sh"

# ── configure-devices.sh ────────────────────────────────────
cat > "$LAB_DIR/scripts/configure-devices.sh" << CFGEOF
#!/bin/bash
# configure-devices.sh — Configure SNMP/BGP on all lab devices
set -euo pipefail
LOG=/var/log/ddlab-configure.log
exec > >(tee -a "\$LOG") 2>&1

SNMP_V3_USER="$SNMP_V3_USER"
SNMP_V3_AUTH="$SNMP_V3_AUTH_PASS"
SNMP_V3_PRIV="$SNMP_V3_PRIV_PASS"
SNMP_COMM="$SNMP_COMMUNITY"
AGENT_IP="$AGENT_MGMT_IP"
DEVICE_PASS="$DEVICE_PASSWORD"
CSR_IP="$CSR_MGMT_IP"
PAN_IP="$PAN_MGMT_IP"
F5_ACTIVE_IP="$F5_ACTIVE_MGMT_IP"
F5_STANDBY_IP="$F5_STANDBY_MGMT_IP"
BGP_LOCAL_AS="$BGP_LOCAL_AS"
BGP_PEER_AS="$BGP_PEER_AS"

echo "[$(date)] Configuring devices..."

# ── CSR: SNMP + BGP ─────────────────────────────────────────
echo "[$(date)] Configuring Cisco CSR..."
sshpass -p "\$DEVICE_PASS" ssh -o StrictHostKeyChecking=no \
  -o ConnectTimeout=30 \
  cisco@"\$CSR_IP" << CSRCMDS
enable
configure terminal
ip access-list standard ACL-SNMP
 permit \$AGENT_IP
snmp-server view ViewAll iso included
snmp-server group DDGroup v3 priv read ViewAll access ACL-SNMP
snmp-server user \$SNMP_V3_USER DDGroup v3 auth sha \$SNMP_V3_AUTH priv aes 128 \$SNMP_V3_PRIV
snmp-server community \$SNMP_COMM RO ACL-SNMP
snmp-server location Bangkok-DC1-Core
snmp-server contact noc@lab.local
snmp-server enable traps bgp
snmp-server host \$AGENT_IP version 3 priv \$SNMP_V3_USER
cdp run
interface GigabitEthernet2
 cdp enable
interface GigabitEthernet3
 cdp enable
router bgp \$BGP_LOCAL_AS
 bgp router-id 172.20.20.10
 neighbor 172.16.0.1 remote-as \$BGP_PEER_AS
 neighbor 172.16.0.1 description FRR-Internet-Sim
 address-family ipv4
  neighbor 172.16.0.1 activate
  network 192.168.10.0 mask 255.255.255.0
wr mem
end
CSRCMDS
echo "[OK] CSR configured."

# ── PAN: SNMP + Zone Protection + Security Policy ───────────
echo "[$(date)] Configuring Palo Alto PA-VM..."
PAN_CMDS=\$(cat << PANCMDS
configure
set network profiles zone-protection-profile lab-zone-protect icmp suppress-icmp-ttl-expired no
set network profiles zone-protection-profile lab-zone-protect icmp discard-icmp-embedded-with-error-message no
set network zone trust zone-protection-profile lab-zone-protect
set network zone untrust zone-protection-profile lab-zone-protect
set network profiles interface-management-profile allow-icmp-ndm ping yes
set network interface ethernet ethernet1/1 layer3 interface-management-profile allow-icmp-ndm
set network interface ethernet ethernet1/2 layer3 interface-management-profile allow-icmp-ndm
set network interface ethernet ethernet1/1 lldp enable yes
set network interface ethernet ethernet1/2 lldp enable yes
set rulebase security rules allow-traceroute-ndm from trust to untrust source 172.20.20.0/24 destination any application [ icmp ping traceroute ] service application-default action allow log-start yes log-end yes
set rulebase security rules allow-icmp-errors-return from untrust to trust source any destination 172.20.20.0/24 application [ icmp ping ] service application-default action allow log-end yes
commit
PANCMDS
)
sshpass -p "Admin@123" ssh -o StrictHostKeyChecking=no \
  -o ConnectTimeout=60 \
  admin@"\$PAN_IP" "\$PAN_CMDS" || echo "[WARN] PAN SSH config may need manual verification"
echo "[OK] PAN configuration attempted."

# ── F5 Active: SNMP + conditional LTM ──────────────────────
F5_LICENSE_KEY="$F5_LICENSE_KEY"

configure_f5_snmp() {
  local ip="\$1"
  echo "[$(date)] Configuring F5 BIG-IP SNMP at \$ip via REST API..."
  local F5_AUTH="admin:\$DEVICE_PASS"
  local F5_URL="https://\$ip/mgmt/tm"

  # Wait for F5 REST API
  for attempt in \$(seq 1 20); do
    if curl -sk -u "\$F5_AUTH" "\$F5_URL/sys/version" >/dev/null 2>&1; then
      echo "  F5 REST API ready."
      break
    fi
    echo "  Waiting for F5 REST API... (\$attempt/20)"
    sleep 15
  done

  # DNS
  curl -sk -u "\$F5_AUTH" -X PATCH "\$F5_URL/sys/dns" \
    -H "Content-Type: application/json" \
    -d '{"nameServers":["8.8.8.8","8.8.4.4"],"search":["lab.local"]}' >/dev/null 2>&1

  # SNMP allowed addresses
  curl -sk -u "\$F5_AUTH" -X PATCH "\$F5_URL/sys/snmp" \
    -H "Content-Type: application/json" \
    -d "{\"allowedAddresses\":[\"127.0.0.0/8\",\"172.20.20.0/24\"]}" >/dev/null 2>&1

  # SNMPv2c community
  curl -sk -u "\$F5_AUTH" -X POST "\$F5_URL/sys/snmp/communities" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"\$SNMP_COMM\",\"communityName\":\"\$SNMP_COMM\",\"access\":\"ro\",\"source\":\"172.20.20.0/24\"}" >/dev/null 2>&1

  # Save
  curl -sk -u "\$F5_AUTH" -X POST "\$F5_URL/sys/config" \
    -H "Content-Type: application/json" -d '{"command":"save"}' >/dev/null 2>&1
  echo "[OK] F5 SNMP configured at \$ip."
}

configure_f5_ltm() {
  local ip="\$1"
  local license_key="\$2"
  local F5_AUTH="admin:\$DEVICE_PASS"
  local F5_URL="https://\$ip/mgmt/tm"

  echo "[$(date)] Licensing F5 BIG-IP at \$ip..."
  curl -sk -u "\$F5_AUTH" -X POST "\$F5_URL/sys/license" \
    -H "Content-Type: application/json" \
    -d "{\"command\":\"install\",\"registrationKey\":\"\$license_key\"}" 2>/dev/null
  sleep 10

  # Verify license
  local lic_check
  lic_check=\$(curl -sk -u "\$F5_AUTH" "\$F5_URL/sys/license" 2>/dev/null)
  if echo "\$lic_check" | grep -q "entries"; then
    echo "[OK] F5 licensed successfully."
  else
    echo "[WARN] License may not have applied. Attempting LTM setup anyway..."
  fi

  # Create VLAN + self-IP
  curl -sk -u "\$F5_AUTH" -X POST "\$F5_URL/net/vlan" -H "Content-Type: application/json" \
    -d '{"name":"external","tag":4094,"interfaces":[{"name":"1.1","untagged":true}]}' >/dev/null 2>&1
  curl -sk -u "\$F5_AUTH" -X POST "\$F5_URL/net/self" -H "Content-Type: application/json" \
    -d '{"name":"external-self","address":"192.168.30.1/24","vlan":"/Common/external","allowService":"all"}' >/dev/null 2>&1

  # Resolve shopist.io
  local SHOPIST_IP
  SHOPIST_IP=\$(host -t A shopist.io 2>/dev/null | awk '/has address/{print \$4; exit}')
  if [ -z "\$SHOPIST_IP" ]; then SHOPIST_IP="18.155.68.34"; fi
  local SHOPIST_IP2
  SHOPIST_IP2=\$(host -t A shopist.io 2>/dev/null | awk '/has address/{print \$4}' | sed -n 2p)
  if [ -z "\$SHOPIST_IP2" ]; then SHOPIST_IP2="18.155.68.43"; fi

  # HTTP monitor
  curl -sk -u "\$F5_AUTH" -X POST "\$F5_URL/ltm/monitor/http" -H "Content-Type: application/json" \
    -d '{"name":"shopist-monitor","send":"GET / HTTP/1.1\r\nHost: shopist.io\r\n\r\n","recv":"200","interval":30,"timeout":91}' >/dev/null 2>&1

  # Pool with shopist.io backends
  curl -sk -u "\$F5_AUTH" -X POST "\$F5_URL/ltm/pool" -H "Content-Type: application/json" \
    -d "{\"name\":\"shopist-pool\",\"loadBalancingMode\":\"round-robin\",\"monitor\":\"/Common/shopist-monitor\",\"members\":[\"\$SHOPIST_IP:443\",\"\$SHOPIST_IP2:443\"]}" >/dev/null 2>&1

  # Server-SSL profile (F5 -> shopist.io HTTPS)
  curl -sk -u "\$F5_AUTH" -X POST "\$F5_URL/ltm/profile/server-ssl" -H "Content-Type: application/json" \
    -d '{"name":"shopist-serverssl","defaultsFrom":"/Common/serverssl","serverName":"shopist.io"}' >/dev/null 2>&1

  # Virtual server: HTTP 80 -> shopist.io 443
  local vip_result
  vip_result=\$(curl -sk -w "%%{http_code}" -u "\$F5_AUTH" -X POST "\$F5_URL/ltm/virtual" -H "Content-Type: application/json" \
    -d '{
      "name":"shopist-vip",
      "destination":"192.168.30.100:80",
      "ipProtocol":"tcp",
      "pool":"/Common/shopist-pool",
      "sourceAddressTranslation":{"type":"automap"},
      "profiles":[
        {"name":"/Common/http","context":"all"},
        {"name":"/Common/shopist-serverssl","context":"serverside"},
        {"name":"/Common/tcp","context":"all"}
      ]
    }' 2>/dev/null)

  if echo "\$vip_result" | grep -q "200\|shopist-vip"; then
    echo "[OK] F5 LTM VIP created: 192.168.30.100:80 -> shopist.io:443"
  else
    echo "[FAIL] F5 LTM VIP creation failed (license may be invalid)."
    echo "  Falling back to nginx reverse proxy..."
    deploy_nginx_shopist_proxy
    return
  fi

  curl -sk -u "\$F5_AUTH" -X POST "\$F5_URL/sys/config" \
    -H "Content-Type: application/json" -d '{"command":"save"}' >/dev/null 2>&1
  echo "[OK] F5 LTM fully configured with shopist.io VIP."
}

deploy_nginx_shopist_proxy() {
  echo "[$(date)] Deploying nginx reverse proxy for shopist.io (F5 LTM not licensed)..."

  cat > /opt/ddlab/configs/nginx-shopist.conf << 'NGINX_CFG'
worker_processes 1;
events { worker_connections 128; }
http {
    resolver 8.8.8.8 valid=60s;
    resolver_timeout 5s;
    log_format main '\$remote_addr [\$time_local] "\$request" \$status \$body_bytes_sent rt=\$request_time';
    access_log /dev/stdout main;
    error_log /dev/stderr warn;
    server {
        listen 80;
        server_name _;
        location / {
            proxy_pass https://shopist.io;
            proxy_set_header Host shopist.io;
            proxy_set_header X-Real-IP \$remote_addr;
            proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
            proxy_ssl_server_name on;
            proxy_ssl_name shopist.io;
            proxy_connect_timeout 10s;
            proxy_read_timeout 30s;
        }
        location /health {
            return 200 '{"status":"ok","backend":"shopist.io","via":"nginx-lb"}';
            add_header Content-Type application/json;
        }
    }
}
NGINX_CFG

  docker rm -f shopist-lb 2>/dev/null || true
  docker run -d \
    --name shopist-lb \
    --network clab \
    --ip 172.20.20.100 \
    -v /opt/ddlab/configs/nginx-shopist.conf:/etc/nginx/nginx.conf:ro \
    --restart unless-stopped \
    --dns 8.8.8.8 \
    nginx:alpine
  echo "[OK] nginx reverse proxy deployed at 172.20.20.100:80 -> shopist.io"
}

# F5/PAN removed from topology — topology is now CSR1000v-only. All SNMP
# config is baked into the vrnetlab startup-config files for each CSR,
# so no post-deploy device configuration is required here.
echo "[$(date)] CSR-only topology — no post-deploy device config needed."

echo "[$(date)] All device configurations complete."
CFGEOF
chmod +x "$LAB_DIR/scripts/configure-devices.sh"

# ── register-geomap.sh ──────────────────────────────────────
cat > "$LAB_DIR/scripts/register-geomap.sh" << GEOEOF
#!/bin/bash
# register-geomap.sh — Register Datadog NDM Geomap locations via API
# Thailand: Bangkok DC1 (CSR + PAN) and Chiang Mai DC2 (F5 Active + Standby)
set -euo pipefail

DD_API_KEY="$DD_API_KEY"
DD_SITE="$DD_SITE"
DD_API_BASE="https://api.\$DD_SITE"
LOG=/var/log/ddlab-geomap.log
exec > >(tee -a "\$LOG") 2>&1

echo "[$(date)] Registering Datadog NDM Geomap locations for Thailand..."

# Datadog Geomap uses the NDM device tags API to set geolocation tags,
# then the Settings page to map geolocation tag values to coordinates.
# This script:
#   1. Applies geolocation tags to devices via NDM Tags API
#   2. Outputs the manual steps needed in the Datadog UI for coordinate mapping

BKK_GEO="bkk-dc1"
CNX_GEO="cnx-dc2"
BKK_LAT="$GEO_BKK_LAT"
BKK_LON="$GEO_BKK_LON"
CNX_LAT="$GEO_CNX_LAT"
CNX_LON="$GEO_CNX_LON"

# Helper: patch device tags via NDM API
patch_device_tags() {
  local device_ip="\$1"
  local geo_tag="\$2"
  local site_tag="\$3"
  local vendor="\$4"
  local device_type="\$5"

  echo "[$(date)] Tagging device \$device_ip with geolocation:\$geo_tag..."
  curl -s -X PATCH "\$DD_API_BASE/api/v2/ndm/tags/devices/snmp%3A\$${device_ip}%3Adefault%3A$DD_NAMESPACE" \
    -H "Content-Type: application/json" \
    -H "DD-API-KEY: \$DD_API_KEY" \
    -d "{
      \"data\": {
        \"type\": \"ndm_device_user_tags\",
        \"attributes\": {
          \"tags\": [
            \"geolocation:\$geo_tag\",
            \"site:\$site_tag\",
            \"vendor:\$vendor\",
            \"device_type:\$device_type\",
            \"env:lab\",
            \"namespace:$DD_NAMESPACE\"
          ]
        }
      }
    }" | jq '.' || echo "[WARN] Tag patch for \$device_ip returned non-JSON or failed"
}

# CSR-only topology: CSR1 Bangkok, CSR2 WAN Transit, CSR3 Chiang Mai
patch_device_tags "$CSR_MGMT_IP"   "\$BKK_GEO"     "$GEO_BKK_LABEL" "cisco" "router"
patch_device_tags "$CSR2_MGMT_IP"  "wan-transit"   "WAN-Transit"    "cisco" "router"
patch_device_tags "$CSR3_MGMT_IP"  "\$CNX_GEO"     "$GEO_CNX_LABEL" "cisco" "router"

echo ""
echo "============================================================"
echo "  GEOMAP COORDINATE MAPPING — Manual UI Steps Required"
echo "============================================================"
echo ""
echo "  1. Open: \$DD_APP_URL/devices"
echo "  2. Click: Settings (top right) > Geomap"
echo "  3. Click: '+ Add Mapping'"
echo ""
echo "  Add these two location mappings:"
echo ""
echo "  Location Tag Value : bkk-dc1"
echo "  Latitude           : \$BKK_LAT"
echo "  Longitude          : \$BKK_LON"
echo "  Display Name       : $GEO_BKK_LABEL"
echo "  Devices            : CSR Router, PAN Firewall"
echo ""
echo "  Location Tag Value : cnx-dc2"
echo "  Latitude           : \$CNX_LAT"
echo "  Longitude          : \$CNX_LON"
echo "  Display Name       : $GEO_CNX_LABEL"
echo "  Devices            : F5 Active, F5 Standby"
echo ""
echo "  Alternatively run the CSV import:"
echo "  File: /opt/ddlab/geomap-locations.csv"
echo "============================================================"

# Write the CSV for import in UI
cat > /opt/ddlab/geomap-locations.csv << CSVEOF
geolocation_tag_value,latitude,longitude,display_name
bkk-dc1,\$BKK_LAT,\$BKK_LON,$GEO_BKK_LABEL
cnx-dc2,\$CNX_LAT,\$CNX_LON,$GEO_CNX_LABEL
CSVEOF

echo "[$(date)] Geomap registration complete."
echo "  CSV exported to: /opt/ddlab/geomap-locations.csv"
GEOEOF
chmod +x "$LAB_DIR/scripts/register-geomap.sh"

# ── validate.sh ─────────────────────────────────────────────
cat > "$LAB_DIR/scripts/validate.sh" << VALEOF
#!/bin/bash
# validate.sh — End-to-end validation of the DDLab NDM setup
set -uo pipefail

PASS=0
FAIL=0
WARN=0
AGENT_CONTAINER="clab-$${CLAB_NAME}-dd-agent"

green() { echo -e "\033[32m[PASS]\033[0m \$1"; }
red()   { echo -e "\033[31m[FAIL]\033[0m \$1"; }
warn()  { echo -e "\033[33m[WARN]\033[0m \$1"; }
hdr()   { echo -e "\n\033[1;34m=== \$1 ===\033[0m"; }

check() {
  local desc="\$1"; shift
  if "\$@" &>/dev/null; then
    green "\$desc"
    PASS=\$((PASS+1))
  else
    red "\$desc"
    FAIL=\$((FAIL+1))
  fi
}

echo "============================================================"
echo "  Datadog NDM Lab — Validation Report"
echo "  \$(date)"
echo "============================================================"

hdr "KVM & Docker"
check "KVM device accessible"             ls /dev/kvm
check "Docker daemon running"             docker info
check "Containerlab installed"            containerlab version
check "dd-agent container running"        docker ps --filter "name=\$AGENT_CONTAINER" --filter "status=running" -q

hdr "Containerlab Topology"
check "CSR1 container running"            docker ps --filter "name=clab-$${CLAB_NAME}-csr\$" -q
check "CSR2 container running"            docker ps --filter "name=clab-$${CLAB_NAME}-csr2" -q
check "CSR3 container running"            docker ps --filter "name=clab-$${CLAB_NAME}-csr3" -q
check "CSR4 container running"            docker ps --filter "name=clab-$${CLAB_NAME}-csr4" -q
check "CSR5 container running"            docker ps --filter "name=clab-$${CLAB_NAME}-csr5" -q
check "BGP peer (FRR) running"            docker ps --filter "name=clab-$${CLAB_NAME}-bgp-peer" -q

hdr "SNMP Connectivity"
for ip in $CSR_MGMT_IP $CSR2_MGMT_IP $CSR3_MGMT_IP $CSR4_MGMT_IP $CSR5_MGMT_IP; do
  check "SNMP reachable: \$ip"  docker exec "\$AGENT_CONTAINER" \
    datadog-agent snmp walk "\$ip" -v 3 \
    --username $SNMP_V3_USER \
    --auth-protocol SHA --auth-key "$SNMP_V3_AUTH_PASS" \
    --priv-protocol AES --priv-key "$SNMP_V3_PRIV_PASS" \
    1.3.6.1.2.1.1.1.0 2>&1 | grep -q "1.3.6"
done

hdr "Network Connectivity"
for ip in $CSR_MGMT_IP $PAN_MGMT_IP $F5_ACTIVE_MGMT_IP $F5_STANDBY_MGMT_IP; do
  check "Ping: \$ip"  docker exec "\$AGENT_CONTAINER" ping -c 2 -W 3 "\$ip"
done

hdr "Traceroute (PAN visibility)"
TRACE_OUT=\$(docker exec "\$AGENT_CONTAINER" traceroute -I -m 6 $F5_ACTIVE_MGMT_IP 2>&1 || true)
if echo "\$TRACE_OUT" | grep -q "$PAN_MGMT_IP"; then
  green "PAN visible as hop in traceroute to F5"
  PASS=\$((PASS+1))
else
  warn "PAN ($PAN_MGMT_IP) not visible as traceroute hop — check Zone Protection config"
  WARN=\$((WARN+1))
fi

hdr "Datadog Agent Status"
AGENT_STATUS=\$(docker exec "\$AGENT_CONTAINER" datadog-agent status 2>/dev/null || echo "")
if echo "\$AGENT_STATUS" | grep -q "snmp"; then
  green "Agent SNMP check running"
  PASS=\$((PASS+1))
else
  warn "Agent SNMP check not found in status — may still be starting"
  WARN=\$((WARN+1))
fi
if echo "\$AGENT_STATUS" | grep -q "network_path"; then
  green "Agent network_path check running"
  PASS=\$((PASS+1))
else
  warn "Agent network_path check not found — check system-probe"
  WARN=\$((WARN+1))
fi

hdr "Summary"
echo "  PASS: \$PASS"
echo "  WARN: \$WARN"
echo "  FAIL: \$FAIL"

if [ "\$FAIL" -gt 0 ]; then
  echo ""
  echo "  Some checks failed. Review logs:"
  echo "    /var/log/ddlab-startup.log"
  echo "    /var/log/ddlab-deploy.log"
  echo "    /var/log/ddlab-configure.log"
  echo "    docker logs <container-name>"
  exit 1
fi

echo ""
echo "  Lab is ready. Open Datadog:"
echo "  NDM:          $DD_APP_URL/devices"
echo "  Network Path: $DD_APP_URL/network/path"
echo "  Topology Map: $DD_APP_URL/devices/topology"
echo "  Geomap:       $DD_APP_URL/devices/geomap"
VALEOF
chmod +x "$LAB_DIR/scripts/validate.sh"

# ── teardown.sh ─────────────────────────────────────────────
cat > "$LAB_DIR/scripts/teardown.sh" << TEAREOF
#!/bin/bash
# teardown.sh — Destroy Containerlab topology (preserves images)
set -euo pipefail
echo "Destroying Containerlab topology..."
sudo containerlab destroy \
  --topo /opt/ddlab/containerlab/ndm-lab.clab.yml \
  --cleanup
echo "Lab topology destroyed. VM images on disk are preserved."
echo "To redeploy: bash /opt/ddlab/scripts/deploy-lab.sh"
TEAREOF
chmod +x "$LAB_DIR/scripts/teardown.sh"

# ── simulate-latency.sh ─────────────────────────────────────
cat > "$LAB_DIR/scripts/simulate-latency.sh" << 'LATEOF'
#!/bin/bash
# simulate-latency.sh — Inject/remove latency on CSR2 WAN transit hop
# This causes Network Path to show elevated hop latency on CSR2,
# simulating a degraded WAN link between Bangkok DC1 and Chiang Mai DC2.
#
# Usage:
#   simulate-latency.sh on  [ms] [jitter_ms]   — Add latency (default 200ms, jitter 50ms)
#   simulate-latency.sh off                     — Remove latency
#   simulate-latency.sh status                  — Show current tc qdisc rules
set -euo pipefail

CSR2_CONTAINER="clab-ddlab-ndm-csr2"
ACTION="$${1:-status}"
DELAY_MS="$${2:-200}"
JITTER_MS="$${3:-50}"

CSR2_PID=$(docker inspect "$CSR2_CONTAINER" --format '{{.State.Pid}}' 2>/dev/null)
if [ -z "$CSR2_PID" ] || [ "$CSR2_PID" = "0" ]; then
  echo "[ERROR] CSR2 container not running"; exit 1
fi

run_in_csr2() { nsenter -n -t "$CSR2_PID" -- "$@"; }

case "$ACTION" in
  on)
    echo "Injecting $${DELAY_MS}ms latency (±$${JITTER_MS}ms jitter) on CSR2 transit interfaces..."
    for iface in eth1 eth2; do
      run_in_csr2 tc qdisc del dev "$iface" root 2>/dev/null || true
      run_in_csr2 tc qdisc add dev "$iface" root netem delay "$${DELAY_MS}ms" "$${JITTER_MS}ms" distribution normal
      echo "  [ON] $iface: $${DELAY_MS}ms ± $${JITTER_MS}ms"
    done
    echo ""
    echo "Latency injection ACTIVE. Datadog Network Path will show elevated RTT"
    echo "on hop 2 (CSR2) within 1-2 minutes."
    echo ""
    echo "To remove: $0 off"
    ;;
  off)
    echo "Removing latency injection from CSR2 transit interfaces..."
    for iface in eth1 eth2; do
      run_in_csr2 tc qdisc del dev "$iface" root 2>/dev/null || true
      echo "  [OFF] $iface: latency removed"
    done
    echo ""
    echo "Latency injection REMOVED. Network Path RTT will return to normal."
    ;;
  status)
    echo "CSR2 tc qdisc rules:"
    for iface in eth1 eth2; do
      echo "  $iface:"
      run_in_csr2 tc qdisc show dev "$iface" 2>/dev/null | sed 's/^/    /'
    done
    ;;
  *)
    echo "Usage: $0 {on [delay_ms] [jitter_ms] | off | status}"
    exit 1
    ;;
esac
LATEOF
chmod +x "$LAB_DIR/scripts/simulate-latency.sh"

# ── simulate-packet-loss.sh ──────────────────────────────────
cat > "$LAB_DIR/scripts/simulate-packet-loss.sh" << 'PLEOF'
#!/bin/bash
# simulate-packet-loss.sh — Inject/remove packet loss on a router link
#
# Usage:
#   simulate-packet-loss.sh on  [router] [percent]  — Add loss (default: csr2, 10%)
#   simulate-packet-loss.sh off [router]             — Remove loss
#   simulate-packet-loss.sh status [router]          — Show current rules
set -euo pipefail

ACTION="$${1:-status}"
ROUTER="$${2:-csr2}"
LOSS_PCT="$${3:-10}"
CONTAINER="clab-ddlab-ndm-$${ROUTER}"

PID=$(docker inspect "$CONTAINER" --format '{{.State.Pid}}' 2>/dev/null)
if [ -z "$PID" ] || [ "$PID" = "0" ]; then
  echo "[ERROR] Container $CONTAINER not running"; exit 1
fi

run_in() { nsenter -n -t "$PID" -- "$@"; }

case "$ACTION" in
  on)
    echo "Injecting $${LOSS_PCT}% packet loss on $ROUTER transit interfaces..."
    for iface in eth1 eth2; do
      run_in tc qdisc del dev "$iface" root 2>/dev/null || true
      run_in tc qdisc add dev "$iface" root netem loss "$${LOSS_PCT}%"
      echo "  [ON] $iface: $${LOSS_PCT}% loss"
    done
    echo ""
    echo "Packet loss active. SNMP ifInErrors/ifOutDiscards counters will increase."
    echo "To remove: $0 off $ROUTER"
    ;;
  off)
    echo "Removing packet loss from $ROUTER transit interfaces..."
    for iface in eth1 eth2; do
      run_in tc qdisc del dev "$iface" root 2>/dev/null || true
      echo "  [OFF] $iface: loss removed"
    done
    ;;
  status)
    echo "$ROUTER tc qdisc rules:"
    for iface in eth1 eth2; do
      echo "  $iface:"
      run_in tc qdisc show dev "$iface" 2>/dev/null | sed 's/^/    /'
    done
    ;;
  *)
    echo "Usage: $0 {on [router] [percent] | off [router] | status [router]}"
    exit 1
    ;;
esac
PLEOF
chmod +x "$LAB_DIR/scripts/simulate-packet-loss.sh"

# ── simulate-bgp-flap.sh ────────────────────────────────────
cat > "$LAB_DIR/scripts/simulate-bgp-flap.sh" << 'BGPEOF'
#!/bin/bash
# simulate-bgp-flap.sh — Cause BGP session flapping on a CSR router
# Shuts down the BGP peer-facing interface, waits, then restores it.
# Generates SNMP traps: bgpBackwardTransition / bgpEstablished, linkDown / linkUp
#
# Usage:
#   simulate-bgp-flap.sh [router_ip] [down_seconds] [flap_count]
#   simulate-bgp-flap.sh                           — flap CSR1 eBGP once, 30s down
#   simulate-bgp-flap.sh 172.20.20.10 60 3         — flap CSR1 3 times, 60s each
set -euo pipefail

ROUTER_IP="$${1:-172.20.20.10}"
DOWN_SECS="$${2:-30}"
FLAP_COUNT="$${3:-1}"
USER="admin"
PASS="admin"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o Ciphers=+aes128-cbc,aes256-cbc"

if [ "$ROUTER_IP" = "172.20.20.10" ]; then
  IFACE="GigabitEthernet2"
  echo "Target: CSR1 BKK-Edge — eBGP peer link ($IFACE to FRR)"
elif [ "$ROUTER_IP" = "172.20.20.11" ]; then
  IFACE="GigabitEthernet2"
  echo "Target: CSR2 WAN-Core — iBGP link ($IFACE to CSR1)"
elif [ "$ROUTER_IP" = "172.20.20.12" ]; then
  IFACE="GigabitEthernet2"
  echo "Target: CSR3 CNX-Edge — iBGP link ($IFACE to CSR2)"
else
  echo "[ERROR] Unknown router IP. Use 172.20.20.10, .11, or .12"
  exit 1
fi

echo "Will flap $IFACE $FLAP_COUNT time(s), $${DOWN_SECS}s down each."
echo ""

for i in $(seq 1 "$FLAP_COUNT"); do
  echo "[Flap $i/$FLAP_COUNT] Shutting down $IFACE on $ROUTER_IP..."
  sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$ROUTER_IP" << EOF
configure terminal
interface $IFACE
shutdown
end
EOF
  echo "  Interface DOWN. Waiting $${DOWN_SECS}s..."
  echo "  → Expect SNMP traps: linkDown, bgpBackwardTransition"
  sleep "$DOWN_SECS"

  echo "  Restoring $IFACE..."
  sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$ROUTER_IP" << EOF
configure terminal
interface $IFACE
no shutdown
end
EOF
  echo "  Interface UP."
  echo "  → Expect SNMP traps: linkUp, bgpEstablished"

  if [ "$i" -lt "$FLAP_COUNT" ]; then
    echo "  Waiting 15s before next flap..."
    sleep 15
  fi
done

echo ""
echo "BGP flap simulation complete."
echo "Check Datadog:"
echo "  Trap logs: https://app.datadoghq.com/logs?query=source:snmp-traps"
echo "  NDM:       https://app.datadoghq.com/devices"
BGPEOF
chmod +x "$LAB_DIR/scripts/simulate-bgp-flap.sh"

# ── simulate-interface-down.sh ───────────────────────────────
cat > "$LAB_DIR/scripts/simulate-interface-down.sh" << 'IFEOF'
#!/bin/bash
# simulate-interface-down.sh — Shut/restore a CSR interface
# Generates SNMP linkDown/linkUp traps visible in Datadog NDM and trap logs.
#
# Usage:
#   simulate-interface-down.sh down [router_ip] [interface]
#   simulate-interface-down.sh up   [router_ip] [interface]
#   simulate-interface-down.sh flap [router_ip] [interface] [down_seconds]
set -euo pipefail

ACTION="$${1:-}"
ROUTER_IP="$${2:-172.20.20.10}"
IFACE="$${3:-GigabitEthernet3}"
DOWN_SECS="$${4:-30}"
USER="admin"
PASS="admin"
SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o KexAlgorithms=+diffie-hellman-group14-sha1 -o HostKeyAlgorithms=+ssh-rsa -o Ciphers=+aes128-cbc,aes256-cbc"

case "$ACTION" in
  down)
    echo "Shutting down $IFACE on $ROUTER_IP..."
    sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$ROUTER_IP" << EOF
configure terminal
interface $IFACE
shutdown
end
EOF
    echo "[DOWN] $IFACE on $ROUTER_IP is now administratively down."
    echo "→ Expect: SNMP linkDown trap, interface status change in NDM"
    ;;
  up)
    echo "Restoring $IFACE on $ROUTER_IP..."
    sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$ROUTER_IP" << EOF
configure terminal
interface $IFACE
no shutdown
end
EOF
    echo "[UP] $IFACE on $ROUTER_IP restored."
    echo "→ Expect: SNMP linkUp trap, interface status recovery in NDM"
    ;;
  flap)
    echo "Flapping $IFACE on $ROUTER_IP (down $${DOWN_SECS}s)..."
    sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$ROUTER_IP" << EOF
configure terminal
interface $IFACE
shutdown
end
EOF
    echo "  [DOWN] Waiting $${DOWN_SECS}s..."
    sleep "$DOWN_SECS"
    sshpass -p "$PASS" ssh $SSH_OPTS "$USER@$ROUTER_IP" << EOF
configure terminal
interface $IFACE
no shutdown
end
EOF
    echo "  [UP] Interface restored."
    ;;
  *)
    echo "Usage: $0 {down|up|flap} [router_ip] [interface] [down_seconds]"
    echo ""
    echo "Examples:"
    echo "  $0 down 172.20.20.10 GigabitEthernet3    # Shut CSR1 Gi3"
    echo "  $0 up   172.20.20.10 GigabitEthernet3    # Restore it"
    echo "  $0 flap 172.20.20.11 GigabitEthernet2 60 # Flap CSR2 Gi2 for 60s"
    exit 1
    ;;
esac
IFEOF
chmod +x "$LAB_DIR/scripts/simulate-interface-down.sh"

# ── simulate-cpu-stress.sh ───────────────────────────────────
cat > "$LAB_DIR/scripts/simulate-cpu-stress.sh" << 'CPUEOF'
#!/bin/bash
# simulate-cpu-stress.sh — Spike CPU utilization on a CSR router's QEMU VM
# The vrnetlab container wraps a QEMU process; this stresses the container's
# CPU allocation, which in turn raises the CSR's reported cpmCPUTotal5minRev
# (SNMP OID polled by Datadog NDM).
#
# Usage:
#   simulate-cpu-stress.sh on  [router] [duration_secs]
#   simulate-cpu-stress.sh off [router]
#   simulate-cpu-stress.sh status [router]
set -euo pipefail

ACTION="$${1:-status}"
ROUTER="$${2:-csr}"
DURATION="$${3:-300}"
CONTAINER="clab-ddlab-ndm-$${ROUTER}"

case "$ACTION" in
  on)
    echo "Starting CPU stress in $CONTAINER for $${DURATION}s..."
    docker exec -d "$CONTAINER" sh -c "
      for i in 1 2 3 4; do
        (timeout $DURATION dd if=/dev/urandom of=/dev/null bs=1M &)
      done
    "
    echo "[ON] CPU stress active for $${DURATION}s on $ROUTER."
    echo "     SNMP CPU OIDs will reflect elevated utilization within 5 min."
    echo "To stop early: $0 off $ROUTER"
    ;;
  off)
    echo "Stopping CPU stress in $CONTAINER..."
    docker exec "$CONTAINER" sh -c "pkill -f 'dd if=/dev/urandom' 2>/dev/null || true"
    echo "[OFF] CPU stress stopped on $ROUTER."
    ;;
  status)
    echo "CPU stress processes in $CONTAINER:"
    docker exec "$CONTAINER" sh -c "ps aux | grep -c 'dd if=/dev/urandom' | xargs -I{} echo '  Active stress processes: {}'"
    docker exec "$CONTAINER" sh -c "cat /proc/loadavg" | xargs -I{} echo "  Container load average: {}"
    ;;
  *)
    echo "Usage: $0 {on [router] [duration_secs] | off [router] | status [router]}"
    exit 1
    ;;
esac
CPUEOF
chmod +x "$LAB_DIR/scripts/simulate-cpu-stress.sh"

# ── loadtest.sh — Load test against CSR-WAN-TRANSIT ──────────
# Sends high packet-rate traffic through the CSR1000v chain. A CSR1000v
# without a throughput license caps data-plane forwarding at ~100 Kbps,
# so any sustained burst above that rate WILL cause queueing, loss, and
# latency spikes that NetworkPath will pick up as degraded paths.
cat > "$LAB_DIR/scripts/loadtest.sh" << 'LOADEOF'
#!/bin/bash
# loadtest.sh — Simulated network load test via the CSR1000v chain.
#
# USAGE:
#   loadtest.sh [target] [mode] [duration_secs]
#
# TARGETS:
#   csr2 | csr-wan-transit  (default)  10.100.2.1  — 2 hops from agent
#   csr3 | csr-cnx-edge                 10.100.3.1  — 3 hops
#   csr4 | csr-cnx-access               10.100.4.1  — 4 hops
#   csr5 | csr-cnx-endpoint             10.100.5.1  — 5 hops
#
# MODES:
#   steady    ~100 pps, ~80 Kbps   (fits under the ~100 Kbps unlicensed cap)
#   trickle   ~150 pps, ~150 Kbps  (1.5x cap — subtle loss + latency)
#   burst     ~1000 pps, ~800 Kbps (8x over — clear drops)
#   flood     hping3 --flood        (saturate — heavy drops)
#   overload  ~7000 pps, ~58 Mbps   (explicit overload — near-total drops)
#
# DURATION:  seconds to run (default: 30)
#
# Runs from INSIDE the dd-agent container so traffic uses the eth2
# data-plane link to CSR1 Gi4 and is forwarded down the CSR chain.
set -eu

AGENT=clab-ddlab-ndm-dd-agent
TARGET="$${1:-csr-wan-transit}"
MODE="$${2:-burst}"
DURATION="$${3:-30}"

# ── Resolve friendly name to IP ────────────────────────────────
case "$TARGET" in
  csr2|csr-wan-transit|csr-wan-transit.lab.local)  DEST_IP=10.100.2.1 ;;
  csr3|csr-cnx-edge|csr-cnx-edge.lab.local)        DEST_IP=10.100.3.1 ;;
  csr4|csr-cnx-access|csr-cnx-access.lab.local)    DEST_IP=10.100.4.1 ;;
  csr5|csr-cnx-endpoint|csr-cnx-endpoint.lab.local) DEST_IP=10.100.5.1 ;;
  *) DEST_IP="$TARGET" ;;
esac

# ── Pick hping3 params per mode ────────────────────────────────
# -c = count (for timed runs we use --interval + duration loop)
# -i uX = send every X microseconds
# -d = payload size (bytes)
case "$MODE" in
  steady)   HP_ARGS="-1 -i u10000 -d 100" ;;  # ~100 pps × 128B ≈  80 Kbps (under cap)
  trickle)  HP_ARGS="-1 -i u6600  -d 100" ;;  # ~150 pps × 128B ≈ 150 Kbps (1.5x cap)
  burst)    HP_ARGS="-1 -i u1000  -d 100" ;;  # ~1000 pps × 128B ≈ 800 Kbps (8x cap)
  flood)    HP_ARGS="-1 --flood    -d 100" ;; # max rate — host CPU bound
  overload) HP_ARGS="-1 -i u100   -d 1000" ;; # ~7000 pps × 1KB ≈ 58 Mbps
  *) echo "Unknown mode: $MODE"; exit 1 ;;
esac

cat <<INFO
============================================================
  NETWORK LOAD TEST
  Target:      $TARGET  ($DEST_IP)
  Mode:        $MODE
  Duration:    $${DURATION}s
  Start time:  $(date -u)
  hping3 args: $HP_ARGS
============================================================
CSR1000v unlicensed throughput cap: ~100 Kbps data-plane.
Modes "burst", "flood", "overload" will exceed this cap —
expect drops and latency spikes on NetworkPath dashboards
for paths traversing CSR-WAN-TRANSIT.
============================================================
INFO

# ── Send a Datadog event marking the test window ──────────────
dd_event() {
  local title="$1" text="$2"
  local dd_site dd_api_key api_url
  dd_site=$(docker exec "$AGENT" printenv DD_SITE 2>/dev/null || echo datadoghq.com)
  dd_api_key=$(docker exec "$AGENT" printenv DD_API_KEY 2>/dev/null || echo)
  [ -z "$dd_api_key" ] && { echo "[WARN] DD_API_KEY not available — skipping Datadog event"; return; }
  api_url="https://api.$${dd_site}/api/v1/events"
  curl -sS -X POST "$api_url" \
    -H "Content-Type: application/json" \
    -H "DD-API-KEY: $dd_api_key" \
    -d "{
      \"title\": \"$title\",
      \"text\": \"$text\",
      \"tags\": [\"source:ddlab-ndm\",\"test:loadtest\",\"target:$TARGET\",\"mode:$MODE\"],
      \"alert_type\": \"info\"
    }" >/dev/null && echo "[OK] Datadog event posted: $title"
}

dd_event "LoadTest START — $TARGET/$MODE" \
  "Starting load test: dest=$DEST_IP mode=$MODE duration=$${DURATION}s"

# ── Ensure hping3 present in agent ────────────────────────────
docker exec "$AGENT" bash -c 'command -v hping3 >/dev/null 2>&1 || (apt-get -qq update >/dev/null && apt-get -qq install -y hping3 >/dev/null)'

# ── Baseline ping (control measurement) ───────────────────────
echo ""
echo "─── BASELINE: ping (2 packets) ───"
docker exec "$AGENT" ping -c 2 -W 2 "$DEST_IP" | tail -3

# ── Run load test ─────────────────────────────────────────────
echo ""
echo "─── RUNNING: hping3 $HP_ARGS $DEST_IP for $${DURATION}s ───"
docker exec "$AGENT" timeout "$DURATION" hping3 $HP_ARGS "$DEST_IP" 2>&1 | tail -20 || true

# ── Post-test ping (observe any lingering loss) ───────────────
echo ""
echo "─── POST-TEST: ping (5 packets) ───"
docker exec "$AGENT" ping -c 5 -W 2 "$DEST_IP" | tail -4

# ── Post-test traceroute ──────────────────────────────────────
echo ""
echo "─── POST-TEST: traceroute ───"
docker exec "$AGENT" traceroute -n -I -w 2 -m 10 "$DEST_IP" | head -10

dd_event "LoadTest END — $TARGET/$MODE" \
  "Load test finished: dest=$DEST_IP mode=$MODE duration=$${DURATION}s"

cat <<DONE

============================================================
  LOAD TEST COMPLETE
  End time: $(date -u)

  View NetworkPath impact at:
    https://\$(docker exec "$AGENT" printenv DD_SITE)/network/path
  Filter by tag: path_type:data-plane
  Time range: last 15 minutes
============================================================
DONE
LOADEOF
chmod +x "$LAB_DIR/scripts/loadtest.sh"

# ── simulate-network-faults.sh (all-in-one) ──────────────────
cat > "$LAB_DIR/scripts/simulate-network-faults.sh" << 'FAULTEOF'
#!/bin/bash
# simulate-network-faults.sh — Master simulation controller
# Provides a menu-driven interface to all fault simulation scripts.
#
# Usage: simulate-network-faults.sh
set -euo pipefail

SCRIPTS=/opt/ddlab/scripts
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m'

show_menu() {
  echo ""
  echo -e "$${CYAN}╔══════════════════════════════════════════════════════════╗$${NC}"
  echo -e "$${CYAN}║    Datadog NDM — Network Fault Simulation Controller    ║$${NC}"
  echo -e "$${CYAN}╚══════════════════════════════════════════════════════════╝$${NC}"
  echo ""
  echo -e "$${YELLOW}Network Path Scenarios:$${NC}"
  echo "  1) Inject WAN latency on CSR2         (Network Path hop latency spike)"
  echo "  2) Remove WAN latency from CSR2        (Restore normal latency)"
  echo "  3) Show current latency rules           (tc qdisc status)"
  echo ""
  echo -e "$${YELLOW}Link / Interface Scenarios:$${NC}"
  echo "  4) Shut down an interface               (linkDown trap)"
  echo "  5) Restore an interface                  (linkUp trap)"
  echo "  6) Flap an interface (down + up)         (linkDown + linkUp traps)"
  echo ""
  echo -e "$${YELLOW}BGP Routing Scenarios:$${NC}"
  echo "  7) Flap BGP session on CSR1 (eBGP)      (bgpBackwardTransition trap)"
  echo "  8) Flap BGP session on CSR2 (iBGP)      (bgpBackwardTransition trap)"
  echo ""
  echo -e "$${YELLOW}Device Health Scenarios:$${NC}"
  echo "  9) Spike CPU on a router                 (cpmCPUTotal5minRev high)"
  echo " 10) Stop CPU stress                       (Return CPU to normal)"
  echo ""
  echo -e "$${YELLOW}Packet Loss Scenarios:$${NC}"
  echo " 11) Inject packet loss on CSR2            (Network Path & SNMP errors)"
  echo " 12) Remove packet loss from CSR2          (Restore clean path)"
  echo ""
  echo -e "$${YELLOW}Combined / Demo:$${NC}"
  echo " 13) Full WAN degradation demo             (latency + loss + BGP flap)"
  echo " 14) Reset ALL simulations                 (Clean slate)"
  echo ""
  echo "  0) Exit"
  echo ""
}

while true; do
  show_menu
  read -rp "Select scenario [0-14]: " choice
  echo ""

  case "$choice" in
    1)
      read -rp "  Latency (ms) [200]: " ms; ms="$${ms:-200}"
      read -rp "  Jitter  (ms) [50]:  " jt; jt="$${jt:-50}"
      sudo bash "$SCRIPTS/simulate-latency.sh" on "$ms" "$jt"
      ;;
    2)  sudo bash "$SCRIPTS/simulate-latency.sh" off ;;
    3)  sudo bash "$SCRIPTS/simulate-latency.sh" status ;;
    4)
      read -rp "  Router IP [172.20.20.10]: " rip; rip="$${rip:-172.20.20.10}"
      read -rp "  Interface [GigabitEthernet3]: " iface; iface="$${iface:-GigabitEthernet3}"
      sudo bash "$SCRIPTS/simulate-interface-down.sh" down "$rip" "$iface"
      ;;
    5)
      read -rp "  Router IP [172.20.20.10]: " rip; rip="$${rip:-172.20.20.10}"
      read -rp "  Interface [GigabitEthernet3]: " iface; iface="$${iface:-GigabitEthernet3}"
      sudo bash "$SCRIPTS/simulate-interface-down.sh" up "$rip" "$iface"
      ;;
    6)
      read -rp "  Router IP [172.20.20.10]: " rip; rip="$${rip:-172.20.20.10}"
      read -rp "  Interface [GigabitEthernet3]: " iface; iface="$${iface:-GigabitEthernet3}"
      read -rp "  Down seconds [30]: " ds; ds="$${ds:-30}"
      sudo bash "$SCRIPTS/simulate-interface-down.sh" flap "$rip" "$iface" "$ds"
      ;;
    7)
      read -rp "  Down seconds [30]: " ds; ds="$${ds:-30}"
      read -rp "  Flap count [1]: " fc; fc="$${fc:-1}"
      sudo bash "$SCRIPTS/simulate-bgp-flap.sh" 172.20.20.10 "$ds" "$fc"
      ;;
    8)
      read -rp "  Down seconds [30]: " ds; ds="$${ds:-30}"
      sudo bash "$SCRIPTS/simulate-bgp-flap.sh" 172.20.20.11 "$ds" 1
      ;;
    9)
      read -rp "  Router [csr]: " rtr; rtr="$${rtr:-csr}"
      read -rp "  Duration (s) [300]: " dur; dur="$${dur:-300}"
      sudo bash "$SCRIPTS/simulate-cpu-stress.sh" on "$rtr" "$dur"
      ;;
    10)
      read -rp "  Router [csr]: " rtr; rtr="$${rtr:-csr}"
      sudo bash "$SCRIPTS/simulate-cpu-stress.sh" off "$rtr"
      ;;
    11)
      read -rp "  Loss % [10]: " pct; pct="$${pct:-10}"
      sudo bash "$SCRIPTS/simulate-packet-loss.sh" on csr2 "$pct"
      ;;
    12) sudo bash "$SCRIPTS/simulate-packet-loss.sh" off csr2 ;;
    13)
      echo -e "$${RED}Starting full WAN degradation demo...$${NC}"
      echo "  Step 1: Injecting 200ms latency on CSR2..."
      sudo bash "$SCRIPTS/simulate-latency.sh" on 200 50
      sleep 2
      echo "  Step 2: Adding 5% packet loss on CSR2..."
      sudo bash "$SCRIPTS/simulate-packet-loss.sh" on csr2 5
      sleep 5
      echo "  Step 3: Flapping CSR1 eBGP session (30s down)..."
      sudo bash "$SCRIPTS/simulate-bgp-flap.sh" 172.20.20.10 30 1
      echo ""
      echo -e "$${GREEN}Full demo active. Degradation visible in Datadog within 1-2 min.$${NC}"
      echo "Run option 14 to reset everything."
      ;;
    14)
      echo -e "$${GREEN}Resetting ALL simulations...$${NC}"
      sudo bash "$SCRIPTS/simulate-latency.sh" off 2>/dev/null || true
      sudo bash "$SCRIPTS/simulate-packet-loss.sh" off csr 2>/dev/null || true
      sudo bash "$SCRIPTS/simulate-packet-loss.sh" off csr2 2>/dev/null || true
      sudo bash "$SCRIPTS/simulate-packet-loss.sh" off csr3 2>/dev/null || true
      sudo bash "$SCRIPTS/simulate-cpu-stress.sh" off csr 2>/dev/null || true
      sudo bash "$SCRIPTS/simulate-cpu-stress.sh" off csr2 2>/dev/null || true
      sudo bash "$SCRIPTS/simulate-cpu-stress.sh" off csr3 2>/dev/null || true
      echo -e "$${GREEN}All simulations reset.$${NC}"
      ;;
    0) echo "Bye."; exit 0 ;;
    *) echo -e "$${RED}Invalid choice.$${NC}" ;;
  esac

  echo ""
  read -rp "Press Enter to continue..."
done
FAULTEOF
chmod +x "$LAB_DIR/scripts/simulate-network-faults.sh"

echo "[$(date)] All lab scripts written."

# ============================================================
# STAGE 11 — Pull base Docker images (non-VM ones)
# ============================================================
echo "[$(date)] STAGE 11: Pre-pulling base Docker images..."
docker pull gcr.io/datadoghq/agent:latest    & PULL1=$!
docker pull frrouting/frr:latest    & PULL2=$!
docker pull nginx:alpine            & PULL3=$!
wait $PULL1 $PULL2 $PULL3
echo "[$(date)] Base images pulled."

# ============================================================
# STAGE 12 — Final Permissions
# ============================================================
echo "[$(date)] STAGE 12: Setting final permissions..."
chown -R labuser:labuser "$LAB_DIR"
chown -R labuser:labuser "$VRNL_DIR"

# ============================================================
# STAGE 13 — Auto-provision CSR1000v image + deploy lab
# ============================================================
# Tries in order:
#   (a) GCS cache has a pre-built Docker image tarball → load + deploy
#   (b) GCS cache has the qcow2 → download, build, export tarball back
#       to cache, then deploy
#   (c) Neither — log upload instructions; a subsequent `gcloud compute
#       instances reset` will pick up the qcow2 once uploaded
# ============================================================
echo "[$(date)] STAGE 13: Auto-provision CSR1000v + deploy lab..."

CACHE_BUCKET="$IMAGE_CACHE_BUCKET"
CSR_TAR_OBJ="vrnetlab-cisco_csr1000v.tar.gz"
CSR_QCOW_OBJ="csr1000v.qcow2"
CSR_IMAGE_TAG="${csr_image_tag}"

if [ -z "$CACHE_BUCKET" ]; then
  echo "[STAGE 13] No IMAGE_CACHE_BUCKET set — skipping auto-provision."
  SKIP_DEPLOY=1
fi

# Helper: does a GCS object exist?
gcs_object_exists() {
  gsutil -q stat "gs://$CACHE_BUCKET/$1" 2>/dev/null
}

SKIP_DEPLOY=0
if [ -z "$${SKIP_DEPLOY:-}" ] || [ "$${SKIP_DEPLOY:-0}" = "0" ]; then
  if docker image inspect "$CSR_IMAGE_TAG" >/dev/null 2>&1; then
    echo "[STAGE 13] CSR1000v image already present on this host: $CSR_IMAGE_TAG"
  elif gcs_object_exists "$CSR_TAR_OBJ"; then
    echo "[STAGE 13] Cache HIT: loading pre-built image from gs://$CACHE_BUCKET/$CSR_TAR_OBJ"
    gsutil cp "gs://$CACHE_BUCKET/$CSR_TAR_OBJ" /tmp/csr-image.tar.gz
    docker load -i /tmp/csr-image.tar.gz
    rm -f /tmp/csr-image.tar.gz
    echo "[STAGE 13] Image loaded: $(docker images --format '{{.Repository}}:{{.Tag}}' | grep -E '^vrnetlab/cisco_csr1000v' | head -1)"
  elif gcs_object_exists "$CSR_QCOW_OBJ"; then
    echo "[STAGE 13] Cache has qcow2 but no built image — building (~10 min)..."
    mkdir -p "$VRNL_DIR/csr"
    gsutil cp "gs://$CACHE_BUCKET/$CSR_QCOW_OBJ" "$VRNL_DIR/csr/$CSR_QCOW_OBJ"
    bash "$LAB_DIR/scripts/build-images.sh" || true
    # Export the resulting image back to the cache for future runs
    if docker image inspect "$CSR_IMAGE_TAG" >/dev/null 2>&1; then
      echo "[STAGE 13] Exporting built image → gs://$CACHE_BUCKET/$CSR_TAR_OBJ (~2.4 GB)"
      docker save "$CSR_IMAGE_TAG" | gzip -1 > /tmp/csr-image.tar.gz
      gsutil cp /tmp/csr-image.tar.gz "gs://$CACHE_BUCKET/$CSR_TAR_OBJ"
      rm -f /tmp/csr-image.tar.gz
      echo "[STAGE 13] Cache populated. Subsequent apply cycles will be ~10x faster."
    else
      echo "[STAGE 13] Image build failed — see /var/log/ddlab-build-images.log"
      SKIP_DEPLOY=1
    fi
  else
    cat <<COLDSTART
[STAGE 13] COLD START — cache is empty.

To complete the lab, run the following on your workstation (once):

  gsutil cp <path-to-csr1000v-universalk9.qcow2> \\
           gs://$CACHE_BUCKET/$CSR_QCOW_OBJ

Then reset the VM so the startup script re-runs:

  gcloud compute instances reset $LAB_NAME \\
    --zone=\$(curl -sSf -H 'Metadata-Flavor: Google' \\
         http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ '{print \$NF}') \\
    --project=\$(curl -sSf -H 'Metadata-Flavor: Google' \\
         http://metadata.google.internal/computeMetadata/v1/project/project-id)

The script will download the qcow2, build the vrnetlab image, cache it
back to the bucket (so future runs skip the build), and deploy the lab.
COLDSTART
    SKIP_DEPLOY=1
  fi
fi

if [ "$${SKIP_DEPLOY:-0}" = "0" ]; then
  echo "[STAGE 13] Launching containerlab deploy via systemd (backgrounded)..."
  # Use systemd-run so the deploy keeps going even if the startup script
  # session exits; user can `journalctl -u ddlab-deploy` or tail the log.
  systemctl reset-failed ddlab-deploy.service 2>/dev/null || true
  systemd-run --unit=ddlab-deploy \
    --description="Auto-deploy Datadog NDM lab" \
    --property=StandardOutput=append:/var/log/ddlab-deploy.log \
    --property=StandardError=append:/var/log/ddlab-deploy.log \
    /bin/bash "$LAB_DIR/scripts/deploy-lab.sh"
  echo "[STAGE 13] Deploy started — monitor with: tail -f /var/log/ddlab-deploy.log"
  echo "[STAGE 13] Expect ~7-10 min for all 5 CSRs to boot and register in NDM."
fi

# ============================================================
# DONE
# ============================================================
touch "$LOCK"

echo ""
echo "============================================================"
echo "[$(date)] Bootstrap COMPLETE"
echo "============================================================"
echo ""
echo "CURRENT STATUS:"
if [ "$${SKIP_DEPLOY:-0}" = "0" ]; then
  echo "  Lab auto-deploy is running in background."
  echo "  Monitor: tail -f /var/log/ddlab-deploy.log"
  echo "  Expect the first 5 CSR1000v VMs to be reachable in ~7-10 min."
else
  echo "  Lab deploy was skipped — see STAGE 13 message above."
  echo "  After you upload the qcow2, run:"
  echo "     gcloud compute instances reset $LAB_NAME --zone=<zone> --project=<project>"
fi
echo ""
echo "USEFUL COMMANDS:"
echo "  Follow bootstrap:   tail -f /var/log/ddlab-startup.log"
echo "  Follow deploy:      tail -f /var/log/ddlab-deploy.log"
echo "  Lab status:         sudo containerlab inspect --topo /opt/ddlab/containerlab/ndm-lab.clab.yml"
echo "  Agent status:       sudo docker exec clab-${lab_name}-dd-agent agent status"
echo "  Load test:          sudo bash /opt/ddlab/scripts/loadtest.sh csr-wan-transit trickle 60"
echo "============================================================"
