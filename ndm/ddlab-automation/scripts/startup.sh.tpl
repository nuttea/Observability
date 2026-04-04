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
LAB_NAME="${lab_name}"
LAB_MGMT_SUBNET="${lab_mgmt_subnet}"
SNMP_COMMUNITY="${snmp_community}"
SNMP_V3_USER="${snmp_v3_user}"
SNMP_V3_AUTH_PASS="${snmp_v3_auth_pass}"
SNMP_V3_PRIV_PASS="${snmp_v3_priv_pass}"
DEVICE_PASSWORD="${device_password}"
CSR_MGMT_IP="${csr_mgmt_ip}"
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
# Datadog NDM Containerlab Topology
# Auto-generated by Terraform startup script
# Lab: $LAB_NAME
# ============================================================
name: $CLAB_NAME

topology:
  defaults:
    network-mode: bridge

  nodes:

    # ── Cisco CSR 1000v — BGP Router (Bangkok DC1) ──────────
    csr:
      kind: vr-csr
      image: $CSR_IMAGE
      startup-config: /opt/ddlab/configs/csr-startup.cfg
      mgmt-ipv4: $CSR_MGMT_IP

    # ── Palo Alto PA-VM — Firewall (Bangkok DC1) ─────────────
    panos:
      kind: vr-paloalto_panos
      image: $PAN_IMAGE
      startup-config: /opt/ddlab/configs/pan-startup.xml
      mgmt-ipv4: $PAN_MGMT_IP

    # ── F5 BIG-IP Active (Chiang Mai DC2) ────────────────────
    bigip-active:
      kind: f5_bigip-ve
      image: $F5_IMAGE
      mgmt-ipv4: $F5_ACTIVE_MGMT_IP
      env:
        PASSWORD: "$DEVICE_PASSWORD"

    # ── F5 BIG-IP Standby (Chiang Mai DC2) ───────────────────
    bigip-standby:
      kind: f5_bigip-ve
      image: $F5_IMAGE
      mgmt-ipv4: $F5_STANDBY_MGMT_IP
      env:
        PASSWORD: "$DEVICE_PASSWORD"

    # ── Datadog Agent ─────────────────────────────────────────
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

    # ── FRR BGP Peer (Internet simulation) ───────────────────
    bgp-peer:
      kind: linux
      image: frrouting/frr:latest
      mgmt-ipv4: 172.20.20.6
      binds:
        - /opt/ddlab/configs/frr.conf:/etc/frr/frr.conf

    # ── Backend Web Servers ───────────────────────────────────
    server1:
      kind: linux
      image: nginx:alpine
      mgmt-ipv4: 172.20.20.41

    server2:
      kind: linux
      image: nginx:alpine
      mgmt-ipv4: 172.20.20.42

  links:
    # BGP Peer <-> CSR WAN link
    - endpoints: ["bgp-peer:eth1", "csr:GigabitEthernet2"]
    # CSR <-> PAN untrust
    - endpoints: ["csr:GigabitEthernet3", "panos:Ethernet1/1"]
    # PAN trust <-> F5 Active external
    - endpoints: ["panos:Ethernet1/2", "bigip-active:1.1"]
    # F5 Active <-> F5 Standby HA/mirroring link
    - endpoints: ["bigip-active:1.2", "bigip-standby:1.2"]
    # F5 internal <-> Backend servers
    - endpoints: ["bigip-active:1.3", "server1:eth1"]
    - endpoints: ["bigip-active:1.4", "server2:eth1"]
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
  autodiscovery:
    enabled: true
    workers: 10
    discovery_interval: 300
    loader: core
    use_deduplication: true
    configs:
      - network_address: $LAB_MGMT_SUBNET
        snmp_version: 3
        user: $SNMP_V3_USER
        authProtocol: sha
        authKey: $SNMP_V3_AUTH_PASS
        privProtocol: aes
        privKey: $SNMP_V3_PRIV_PASS
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

# ── SNMP instances.yaml ─────────────────────────────────────
cat > "$LAB_DIR/conf.d/snmp.d/instances.yaml" << SNMP_EOF
instances:

  # ── Cisco CSR (BGP Router — Bangkok DC1) ──────────────────
  - ip_address: $CSR_MGMT_IP
    snmp_version: 3
    user: $SNMP_V3_USER
    authProtocol: sha
    authKey: $SNMP_V3_AUTH_PASS
    privProtocol: aes
    privKey: $SNMP_V3_PRIV_PASS
    loader: core
    tags:
      - "device_type:router"
      - "vendor:cisco"
      - "site:$${GEO_BKK_LABEL}"
      - "geolocation:bkk-dc1"
      - "role:bgp-edge"

  # ── PAN-OS Firewall (Bangkok DC1) ─────────────────────────
  - ip_address: $PAN_MGMT_IP
    snmp_version: 3
    user: $SNMP_V3_USER
    authProtocol: sha
    authKey: $SNMP_V3_AUTH_PASS
    privProtocol: aes
    privKey: $SNMP_V3_PRIV_PASS
    loader: core
    tags:
      - "device_type:firewall"
      - "vendor:paloalto"
      - "site:$${GEO_BKK_LABEL}"
      - "geolocation:bkk-dc1"
      - "role:edge-fw"

  # ── F5 BIG-IP Active (Chiang Mai DC2) ─────────────────────
  - ip_address: $F5_ACTIVE_MGMT_IP
    snmp_version: 3
    user: $SNMP_V3_USER
    authProtocol: sha
    authKey: $SNMP_V3_AUTH_PASS
    privProtocol: aes
    privKey: $SNMP_V3_PRIV_PASS
    loader: core
    tags:
      - "device_type:load_balancer"
      - "vendor:f5"
      - "ha_role:active"
      - "site:$${GEO_CNX_LABEL}"
      - "geolocation:cnx-dc2"
      - "role:ltm-active"

  # ── F5 BIG-IP Standby (Chiang Mai DC2) ────────────────────
  - ip_address: $F5_STANDBY_MGMT_IP
    snmp_version: 3
    user: $SNMP_V3_USER
    authProtocol: sha
    authKey: $SNMP_V3_AUTH_PASS
    privProtocol: aes
    privKey: $SNMP_V3_PRIV_PASS
    loader: core
    tags:
      - "device_type:load_balancer"
      - "vendor:f5"
      - "ha_role:standby"
      - "site:$${GEO_CNX_LABEL}"
      - "geolocation:cnx-dc2"
      - "role:ltm-standby"
SNMP_EOF

# ── SNMP custom profiles ────────────────────────────────────
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

# ── Network Path targets ────────────────────────────────────
cat > "$LAB_DIR/conf.d/network_path.d/conf.yaml" << NP_EOF
instances:
  - hostname: $CSR_MGMT_IP
    protocol: TCP
    port: 22
    tags:
      - "path_name:agent-to-csr"
      - "destination_role:bgp-router"
      - "geolocation:bkk-dc1"
    max_ttl: 10
    traceroute_queries: 3
    e2e_queries: 50
    min_collection_interval: 60

  - hostname: $PAN_MGMT_IP
    protocol: TCP
    port: 443
    tags:
      - "path_name:agent-to-pan"
      - "destination_role:firewall"
      - "geolocation:bkk-dc1"
    max_ttl: 10
    traceroute_queries: 3
    min_collection_interval: 60

  - hostname: $F5_ACTIVE_MGMT_IP
    protocol: TCP
    port: 443
    tags:
      - "path_name:agent-to-f5-active"
      - "destination_role:load-balancer"
      - "geolocation:cnx-dc2"
    max_ttl: 15
    traceroute_queries: 3
    e2e_queries: 50
    min_collection_interval: 60

  - hostname: $F5_STANDBY_MGMT_IP
    protocol: TCP
    port: 443
    tags:
      - "path_name:agent-to-f5-standby"
      - "destination_role:load-balancer-standby"
      - "geolocation:cnx-dc2"
    max_ttl: 15
    traceroute_queries: 3
    min_collection_interval: 120

  - hostname: 192.168.30.100
    protocol: TCP
    port: 80
    tags:
      - "path_name:agent-to-f5-vip-e2e"
      - "destination_role:vip"
      - "geolocation:cnx-dc2"
    max_ttl: 30
    traceroute_queries: 3
    e2e_queries: 50
    tcp_method: sack
    min_collection_interval: 60
NP_EOF

echo "[$(date)] Datadog Agent configs written."

# ============================================================
# STAGE 8 — Render Device Config Files
# ============================================================
echo "[$(date)] STAGE 8: Rendering device startup configs..."

# ── Cisco CSR startup config ────────────────────────────────
cat > "$LAB_DIR/configs/csr-startup.cfg" << CSR_EOF
hostname CSR-BKK-EDGE
!
ip domain-name lab.local
!
! ── Management ──────────────────────────────────────────────
ip access-list standard ACL-SNMP
 permit $AGENT_MGMT_IP
!
! ── SNMPv2c + SNMPv3 ────────────────────────────────────────
snmp-server view ViewAll iso included
snmp-server group DDGroup v3 priv read ViewAll access ACL-SNMP
snmp-server user $SNMP_V3_USER DDGroup v3 auth sha $SNMP_V3_AUTH_PASS priv aes 128 $SNMP_V3_PRIV_PASS
snmp-server community $SNMP_COMMUNITY RO ACL-SNMP
snmp-server location Bangkok-DC1-Core
snmp-server contact noc@lab.local
snmp-server enable traps bgp
snmp-server host $AGENT_MGMT_IP version 3 priv $SNMP_V3_USER
!
! ── CDP for Topology Map ────────────────────────────────────
cdp run
interface GigabitEthernet2
 cdp enable
 no shutdown
interface GigabitEthernet3
 cdp enable
 no shutdown
!
! ── BGP eBGP to FRR (AS $BGP_PEER_AS) ──────────────────────
router bgp $BGP_LOCAL_AS
 bgp router-id 172.20.20.10
 neighbor 172.16.0.1 remote-as $BGP_PEER_AS
 neighbor 172.16.0.1 description FRR-Internet-Sim
 address-family ipv4
  neighbor 172.16.0.1 activate
  network 192.168.10.0 mask 255.255.255.0
!
end
CSR_EOF

# ── FRR BGP peer config ─────────────────────────────────────
cat > "$LAB_DIR/configs/frr.conf" << FRR_EOF
frr version 8.0
frr defaults traditional
hostname bgp-internet-sim
!
router bgp $BGP_PEER_AS
 bgp router-id 172.16.0.1
 neighbor 172.16.0.2 remote-as $BGP_LOCAL_AS
 neighbor 172.16.0.2 description CSR-BKK-EDGE
 !
 address-family ipv4 unicast
  neighbor 172.16.0.2 activate
  network 10.0.0.0/8
 exit-address-family
!
line vty
!
FRR_EOF

# ── PAN-OS startup config (minimal XML bootstrap) ──────────
# Full SNMP/ZP config applied by configure-pan.sh post-boot
cat > "$LAB_DIR/configs/pan-startup.xml" << PAN_EOF
<config version="10.2.0">
  <devices>
    <entry name="localhost.localdomain">
      <deviceconfig>
        <system>
          <hostname>PAN-BKK-FW1</hostname>
          <snmp-setting>
            <access-setting>
              <version>
                <v3>
                  <users>
                    <entry name="$SNMP_V3_USER">
                      <view>default</view>
                      <authpwd>$SNMP_V3_AUTH_PASS</authpwd>
                      <privpwd>$SNMP_V3_PRIV_PASS</privpwd>
                      <authtype>SHA</authtype>
                      <privtype>AES</privtype>
                    </entry>
                  </users>
                </v3>
              </version>
            </access-setting>
            <snmp-system>
              <sysname>PAN-BKK-FW1</sysname>
              <syslocation>Bangkok-DC1-DMZ</syslocation>
              <systrapdest>$AGENT_MGMT_IP</systrapdest>
            </snmp-system>
          </snmp-setting>
        </system>
      </deviceconfig>
    </entry>
  </devices>
</config>
PAN_EOF

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
build_image "F5 BIG-IP VE"   "$VRNL/f5_bigip" "BIGIP-*.qcow2"
build_image "Palo Alto PA-VM" "$VRNL/pan"      "PA-VM-KVM-*.qcow2"

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

echo "[$(date)] Deploying Containerlab topology..."
sudo containerlab deploy --topo "\$TOPO"

echo "[$(date)] Topology deployed. Waiting for VMs to boot..."
echo "  F5 BIG-IP VMs take 10+ minutes. PAN-VM takes ~8 minutes."
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

wait_for_boot "clab-$${CLAB_NAME}-bigip-active"  "Startup complete"   720 || true
wait_for_boot "clab-$${CLAB_NAME}-bigip-standby" "Startup complete"   720 || true
wait_for_boot "clab-$${CLAB_NAME}-panos"          "init: entry 20"     600 || true

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

echo "[$(date)] VMs booted. Running device configuration..."
bash /opt/ddlab/scripts/configure-devices.sh

echo "[$(date)] Deployment complete. Running validation..."
bash /opt/ddlab/scripts/validate.sh
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

# Configure F5 SNMP (always)
configure_f5_snmp "\$F5_ACTIVE_IP"

# License F5 and deploy LTM, or fall back to nginx proxy
if [ -n "\$F5_LICENSE_KEY" ]; then
  echo "[$(date)] F5 license key provided — configuring LTM with shopist.io VIP..."
  configure_f5_ltm "\$F5_ACTIVE_IP" "\$F5_LICENSE_KEY"
else
  echo "[$(date)] No F5 license key — skipping LTM. Deploying nginx proxy instead..."
  deploy_nginx_shopist_proxy
fi

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

# Bangkok DC1 devices
patch_device_tags "$CSR_MGMT_IP"     "\$BKK_GEO" "$GEO_BKK_LABEL" "cisco"     "router"
patch_device_tags "$PAN_MGMT_IP"     "\$BKK_GEO" "$GEO_BKK_LABEL" "paloalto"  "firewall"

# Chiang Mai DC2 devices
patch_device_tags "$F5_ACTIVE_MGMT_IP"  "\$CNX_GEO" "$GEO_CNX_LABEL" "f5" "load_balancer"
patch_device_tags "$F5_STANDBY_MGMT_IP" "\$CNX_GEO" "$GEO_CNX_LABEL" "f5" "load_balancer"

echo ""
echo "============================================================"
echo "  GEOMAP COORDINATE MAPPING — Manual UI Steps Required"
echo "============================================================"
echo ""
echo "  1. Open: https://app.\$DD_SITE/devices"
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
check "CSR container running"             docker ps --filter "name=clab-$${CLAB_NAME}-csr" -q
check "PAN container running"             docker ps --filter "name=clab-$${CLAB_NAME}-panos" -q
check "F5 Active container running"       docker ps --filter "name=clab-$${CLAB_NAME}-bigip-active" -q
check "F5 Standby container running"      docker ps --filter "name=clab-$${CLAB_NAME}-bigip-standby" -q

hdr "SNMP Connectivity"
for ip in $CSR_MGMT_IP $PAN_MGMT_IP $F5_ACTIVE_MGMT_IP $F5_STANDBY_MGMT_IP; do
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
echo "  NDM:          https://app.$DD_SITE/devices"
echo "  Network Path: https://app.$DD_SITE/network/path"
echo "  Topology Map: https://app.$DD_SITE/devices/topology"
echo "  Geomap:       https://app.$DD_SITE/devices/geomap"
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
# DONE
# ============================================================
touch "$LOCK"

echo ""
echo "============================================================"
echo "[$(date)] Bootstrap COMPLETE"
echo "============================================================"
echo ""
echo "NEXT STEPS:"
echo ""
echo "1. Upload your .qcow2 VM images to the instance:"
echo "   scp BIGIP-*.qcow2 labuser@\$(hostname -I | awk '{print \$1}'):/opt/vrnetlab/f5_bigip/"
echo "   scp csr1000v-*.qcow2 labuser@\$(hostname -I | awk '{print \$1}'):/opt/vrnetlab/csr/"
echo "   scp PA-VM-KVM-*.qcow2 labuser@\$(hostname -I | awk '{print \$1}'):/opt/vrnetlab/pan/"
echo ""
echo "2. Build vrnetlab container images:"
echo "   bash /opt/ddlab/scripts/build-images.sh"
echo ""
echo "3. Deploy the lab:"
echo "   bash /opt/ddlab/scripts/deploy-lab.sh"
echo ""
echo "4. Register Geomap locations:"
echo "   bash /opt/ddlab/scripts/register-geomap.sh"
echo ""
echo "5. Run validation:"
echo "   bash /opt/ddlab/scripts/validate.sh"
echo ""
echo "See logs: tail -f /var/log/ddlab-startup.log"
echo "============================================================"
