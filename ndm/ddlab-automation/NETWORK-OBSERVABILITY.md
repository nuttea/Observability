# Network Observability — Demo Playbook

This document is the **customer-facing demo playbook** for the DDLab environment. Use it as a script when running Network Observability demos for prospects: each scenario has a stated business problem, the simulation command, what the customer should look at in the Datadog UI, and a recommended monitor template.

For the lab's setup, architecture, and integration snippets, see [`README.md`](README.md). For operational gotchas, see [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

All simulation scripts are at `/opt/ddlab/scripts/` on the GCE VM.

---

## Why Datadog Network Observability

Most network teams have a stack like this in 2026:

| Need | Legacy tool | Datadog |
|---|---|---|
| SNMP polling, MIB browsing | SolarWinds NPM, LibreNMS, Zabbix | **NDM** ([docs](https://docs.datadoghq.com/network_monitoring/devices/)) |
| Hop-by-hop traceroute | manual `traceroute` from a jumphost, ThousandEyes | **NetworkPath** ([docs](https://docs.datadoghq.com/network_monitoring/network_path/)) |
| Flow analysis | NetFlow Analyzer, Plixer Scrutinizer | **NetFlow** ([docs](https://docs.datadoghq.com/network_monitoring/devices/netflow/)) |
| SNMP traps | trap receivers, syslog forwarders | **SNMP Traps** ([docs](https://docs.datadoghq.com/network_monitoring/devices/snmp_traps/)) |
| Configuration drift / topology | rancid, Oxidized | **Topology Map** ([docs](https://docs.datadoghq.com/network_monitoring/devices/topology_map/)) + Cloud Network Monitoring |

The point of Network Observability in Datadog is that **all of these signals live in one place** with the same tag model (`env`, `service`, `team`, `device_namespace`, `site`) and the same alerting + correlation primitives as APM, logs, and infrastructure metrics. When a customer asks "did this app slowdown coincide with a network issue?" the answer is one click away in a Datadog dashboard, not a war-room with three vendors.

This lab demonstrates **NDM + NetworkPath** specifically. NetFlow, SNMP traps, and CDP/LLDP topology can also be enabled — they're already running in the agent (see `network_devices` block in [`/opt/ddlab/datadog.yaml`](#) on the VM) and just need devices to send to them.

### How NDM works (in 5 lines)

1. Datadog Agent reads `instances.yaml` listing devices to poll (or autodiscovers via subnet sweep).
2. For each device, it issues a `GetRequest sysObjectID.0` and matches the result against a profile (`cisco-csr1000v.yaml` etc.) which declares which OIDs to walk.
3. The agent walks those OIDs every `min_collection_interval` seconds (default 15s).
4. Metrics + tags + metadata are sent to Datadog.
5. UI renders them at [`/devices`](https://docs.datadoghq.com/network_monitoring/devices/) as a fleet inventory with per-device drill-downs.

### How NetworkPath works (in 5 lines)

1. Datadog Agent reads `network_path.d/conf.yaml` listing destinations.
2. For each destination, the agent (via `system-probe`) runs N parallel traceroutes (TCP/UDP/ICMP).
3. For every probe, it captures every hop's IP, RTT, and reachability.
4. Hop metadata is enriched with reverse-DNS / NDM device match.
5. The result is sent to the [`/network/path`](https://docs.datadoghq.com/network_monitoring/network_path/) view as continuous time-series — not just a snapshot.

### What this lab proves

| Demo question | The lab shows |
|---|---|
| "Can we see all our routers in one place?" | 5 CSR1000v's listed at `/devices`, filtered by `device_namespace:lab-th` |
| "Can we see what's between us and an endpoint?" | NetworkPath chain `agent → CSR1 → CSR2 → CSR3 → CSR4 → CSR5` rendered hop-by-hop |
| "Can we tell *which hop* is slow?" | [Scenario 1](#scenario-1--in-transit-hop-latency-spike-network-path) — inject 200 ms on CSR2 and watch hop 2 light up |
| "Can we tell *which device* is dropping traffic?" | [Scenario 2](#scenario-2--device-reachability--ping-loss-network-path) — `tc netem loss 50%` on CSR2 |
| "Can we alert when this happens?" | Each scenario has a `datadog_monitor` Terraform snippet you can copy |
| "Can we correlate with the actual traffic load?" | [`README.md` § Load testing](README.md#load-testing) — overload CSR2 + watch NetworkPath simultaneously |

---

> ## Lab topology (current)
>
> The lab now runs **5 Cisco CSR1000v** routers in an iBGP chain (Cisco-only —
> F5 / PA-VM were removed). Loopback IPs and the data-plane link between the
> agent and CSR1 were renumbered since the earlier drafts of this playbook:
>
> | Role | Router | Mgmt IP | Loopback |
> |---|---|---|---|
> | Hop 1 | `csr1-bkk-edge` | 172.20.20.10 | 10.100.1.1 |
> | Hop 2 | `csr2-wan-transit` | 172.20.20.11 | 10.100.2.1 |
> | Hop 3 | `csr3-cnx-edge` | 172.20.20.12 | 10.100.3.1 |
> | Hop 4 | `csr4-cnx-access` | 172.20.20.14 | 10.100.4.1 |
> | Hop 5 | `csr5-cnx-endpoint` | 172.20.20.15 | 10.100.5.1 |
>
> - Agent data-plane: **`dd-agent eth2 = 10.99.0.2/30`** ↔ **`CSR1 Gi4 = 10.99.0.1/30`**
>   (the addresses were reversed in earlier versions of this doc — addresses in
>   the scenarios below reflect the current config).
> - iBGP inter-router subnets: `10.0.12.0/30` (CSR1↔CSR2), `10.0.23.0/30` (CSR2↔CSR3),
>   `10.0.34.0/30` (CSR3↔CSR4), `10.0.45.0/30` (CSR4↔CSR5).
> - For the SNMP check, all 5 CSRs use the Datadog **Python** `cisco-csr1000v`
>   profile loaded via the **core** loader — see `TROUBLESHOOTING.md`.
>
> **New: load-test script** — `/opt/ddlab/scripts/loadtest.sh` generates traffic
> that exceeds the CSR1000v ~100 Kbps unlicensed data-plane throttle and posts
> start/end events to Datadog so the test window annotates NetworkPath graphs.
> See the main [README.md](README.md#load-testing) for modes (steady / trickle /
> burst / flood / overload).

---

## Quick Reference

| Script | Purpose |
|---|---|
| `simulate-network-faults.sh` | Interactive menu for all scenarios |
| `simulate-latency.sh` | WAN hop latency injection via `tc netem` |
| `simulate-packet-loss.sh` | Packet loss injection on router links |
| `simulate-bgp-flap.sh` | BGP session flapping (shut/no shut peer interface) |
| `simulate-interface-down.sh` | Interface down/up/flap with SNMP traps |
| `simulate-cpu-stress.sh` | Device CPU utilization spike |

### Running the Interactive Menu

```bash
sudo bash /opt/ddlab/scripts/simulate-network-faults.sh
```

This presents a numbered menu with all scenarios below, plus a combined "full WAN degradation" demo and a global reset.

---

## Scenario 1 — In-Transit Hop Latency Spike (Network Path)

### What It Demonstrates

A WAN transit router (CSR2) develops high latency, causing Datadog Network Path to show an elevated RTT on hop 2 of the multi-hop path. This is the classic "which hop is slow?" investigation workflow.

### How It Works

The script uses Linux `tc netem` (traffic control / network emulation) to inject delay on CSR2's data-plane interfaces (`eth1` and `eth2` inside the container's network namespace). These map to CSR2's GigabitEthernet2 and GigabitEthernet3, which carry traffic between CSR1 and CSR3.

```
DD Agent (eth2 = 10.99.0.2)
    │
    ▼ TTL=1 → ICMP Time Exceeded
    CSR1 Gi4 (10.99.0.1)          ← ~1ms (normal)
    │
    ▼ TTL=2 → ICMP Time Exceeded
    CSR2 Gi2 (10.0.12.2)          ← 🔴 200ms+ (latency injected here)
    │
    ▼ TTL=3 → destination reached
    CSR3 Lo0 (10.100.3.1)         ← ~200ms+ (cumulative)
    │
    ▼ ... (TTL=4 → CSR4 Lo0 10.100.4.1, TTL=5 → CSR5 Lo0 10.100.5.1)
```

### Simulate

```bash
# Inject 200ms latency with 50ms jitter
sudo bash /opt/ddlab/scripts/simulate-latency.sh on 200 50

# Check status
sudo bash /opt/ddlab/scripts/simulate-latency.sh status

# Remove
sudo bash /opt/ddlab/scripts/simulate-latency.sh off
```

Custom values:

```bash
# 500ms latency, 100ms jitter
sudo bash /opt/ddlab/scripts/simulate-latency.sh on 500 100

# Extreme: 2000ms (2 seconds) for timeout testing
sudo bash /opt/ddlab/scripts/simulate-latency.sh on 2000 200
```

### What to Observe in Datadog

| Where | What to Look For |
|---|---|
| **Network Path** (`/network/path`) | Hop 2 (CSR2) RTT jumps from ~1ms to ~200ms. The path visualization highlights the degraded hop in red/orange. |
| **Network Path → Path Details** | Click on the path to `10.100.3.1`. The hop-by-hop timeline shows CSR2's latency increase at the exact time injection started. |
| **NDM Devices** (`/devices`) | CSR2's interface metrics may show elevated latency if the device reports it via SNMP. |

### Recommended Monitor

**Network Path Hop Latency** — as Terraform:

```hcl
resource "datadog_monitor" "np_hop_rtt_high" {
  name    = "[NetworkPath] Hop RTT > 100 ms on {{path_name.name}} hop {{hop_index.name}}"
  type    = "metric alert"
  query   = "avg(last_5m):avg:datadog.network_path.path.hop_rtt{path_type:data-plane} by {path_name,hop_index,hop_ip_address} > 100"
  message = <<-EOM
    Hop {{hop_index.name}} ({{hop_ip_address.name}}) on path {{path_name.name}}
    averaged {{value}} ms over the last 5 minutes (threshold 100 ms).

    @netops-oncall

    Investigate:
      - NetworkPath: https://app.datadoghq.com/network/path
      - Cross-reference NDM device for {{hop_ip_address.name}}
      - Datadog event timeline for change windows around this time
  EOM

  monitor_thresholds {
    warning  = 50
    critical = 100
  }

  tags = ["team:netops", "service:network-path", "scenario:hop-latency"]
}
```

Or as a one-liner monitor query you can paste into the [Monitors UI](https://app.datadoghq.com/monitors/manage):

```
avg(last_5m):avg:datadog.network_path.path.hop_rtt{path_type:data-plane} by {path_name,hop_index} > 100
```

The grouping by `hop_index` is the magic — alerts fire **per affected hop**, not for the path as a whole. So a slow CSR2 lights up exactly one alert with a clear "hop 2" identifier instead of every downstream destination.

### Datadog reference

- [NetworkPath: Use Cases](https://docs.datadoghq.com/network_monitoring/network_path/using_network_path/) — UI walkthrough including hop-level drill-down
- [Datadog metrics for NetworkPath](https://docs.datadoghq.com/network_monitoring/network_path/setup/?tab=docker#network-path-metrics) — full list of `datadog.network_path.*` metrics
- [Tag-based monitor scoping](https://docs.datadoghq.com/monitors/configuration/?tab=thresholdalert#alert-grouping) — `by {hop_index}` syntax explained

---

## Scenario 2 — Device Reachability / Ping Loss (Network Path)

### What It Demonstrates

A device becomes partially or fully unreachable due to packet loss. Datadog Network Path shows the reachability percentage dropping, and e2e (end-to-end) probes show packet loss.

### How It Works

The script uses `tc netem loss` to probabilistically drop packets on the router's transit interfaces.

### Simulate

```bash
# 10% packet loss on CSR2
sudo bash /opt/ddlab/scripts/simulate-packet-loss.sh on csr2 10

# 50% loss (severe)
sudo bash /opt/ddlab/scripts/simulate-packet-loss.sh on csr2 50

# Remove
sudo bash /opt/ddlab/scripts/simulate-packet-loss.sh off csr2
```

### What to Observe in Datadog

| Where | What to Look For |
|---|---|
| **Network Path** | Packet loss percentage increases on the path to CSR3. Some hops show `* * *` (unreachable probes). |
| **NDM Devices** | `snmp.ifInErrors` and `snmp.ifOutDiscards` counters increment on CSR2 interfaces. |
| **Network Path → Reachability** | Overall reachability metric drops below 100%. |

### Recommended Monitor

**Network Path Reachability**

```
Metric: datadog.network_path.path.reachable
Filter: path_name:agent-to-csr3-cnx-edge
Alert: avg(last_5m) < 1  (1 = reachable, 0 = unreachable)
```

**Interface Errors**

```
Metric: snmp.ifInErrors (rate)
Filter: snmp_device:172.20.20.11  (CSR2)
Alert: avg(last_5m) > 0
```

---

## Scenario 3 — BGP Routing Protocol Flapping

### What It Demonstrates

A BGP session flaps (goes down and comes back up), causing:
- **SNMP Traps**: `bgpBackwardTransition` (session down) and `bgpEstablished` (session restored)
- **linkDown / linkUp** traps for the physical interface
- Routing table convergence delays
- Temporary unreachability of downstream prefixes

### How It Works

The script SSHs into a CSR router and issues `shutdown` / `no shutdown` on the BGP peer-facing interface. This tears down the BGP session, triggers SNMP traps, and causes route withdrawal.

```
                              ┌──────────┐
FRR (AS 65001) ──── eBGP ────│  CSR1     │──── iBGP ──── CSR2 ──── CSR3
                              │  Gi2: 🔴 │
                              │  shutdown │
                              └──────────┘
                                   │
                              SNMP Traps:
                              • bgpBackwardTransition
                              • linkDown (Gi2)
```

### Simulate

```bash
# Single flap on CSR1 eBGP (30s down)
sudo bash /opt/ddlab/scripts/simulate-bgp-flap.sh

# Triple flap on CSR1 (60s down each) — aggressive instability
sudo bash /opt/ddlab/scripts/simulate-bgp-flap.sh 172.20.20.10 60 3

# Flap CSR2 iBGP link
sudo bash /opt/ddlab/scripts/simulate-bgp-flap.sh 172.20.20.11 30 1
```

### What to Observe in Datadog

| Where | What to Look For |
|---|---|
| **SNMP Trap Logs** (`/logs?query=source:snmp-traps`) | `bgpBackwardTransition` and `bgpEstablished` trap events with the peer IP and AS number. |
| **NDM Devices → CSR1** | BGP peer state metric changes: `bgpPeerState` goes from `6` (established) → `1` (idle) → back to `6`. |
| **NDM Topology** (`/devices/topology`) | The link between CSR1 and FRR (or CSR2) temporarily disappears from the topology map when the interface is down. |
| **Network Path** | During the outage, paths through the downed link show `* * *` or 100% loss for affected hops. |

### Recommended Monitors

**BGP Session Down (SNMP Trap)**

```
Log query: source:snmp-traps snmp_trap_name:bgpBackwardTransition
Alert: count(last_5m) > 0
Severity: P2 (Warning)
```

**BGP Peer State**

```
Metric: snmp.bgpPeerState
Filter: snmp_device:* AND bgp_peer:*
Alert: avg(last_5m) < 6  (6 = established)
```

**BGP Flapping (Multiple Transitions)**

```
Log query: source:snmp-traps (snmp_trap_name:bgpBackwardTransition OR snmp_trap_name:bgpEstablished)
Alert: count(last_15m) > 4  (indicates rapid flapping)
Severity: P1 (Critical)
```

---

## Scenario 4 — Device CPU High

### What It Demonstrates

A network device's CPU utilization spikes, which is detected by Datadog NDM's SNMP polling of CPU OIDs. In production, this often indicates a routing loop, excessive control plane processing, or a DDoS attack.

### How It Works

The script runs CPU-intensive processes (`dd if=/dev/urandom`) inside the vrnetlab container that wraps the CSR's QEMU VM. Since the container has limited CPU shares, this competes with the QEMU process, causing the CSR's internal CPU metrics to rise.

### Simulate

```bash
# Spike CPU on CSR1 for 5 minutes (300s)
sudo bash /opt/ddlab/scripts/simulate-cpu-stress.sh on csr 300

# Check status
sudo bash /opt/ddlab/scripts/simulate-cpu-stress.sh status csr

# Stop early
sudo bash /opt/ddlab/scripts/simulate-cpu-stress.sh off csr

# Stress CSR2 for 10 minutes
sudo bash /opt/ddlab/scripts/simulate-cpu-stress.sh on csr2 600
```

### What to Observe in Datadog

| Where | What to Look For |
|---|---|
| **NDM Devices → CSR1 → Overview** | CPU utilization graph shows a spike. The `cpmCPUTotal5minRev` metric rises. |
| **NDM Devices → CSR1 → Metrics** | `snmp.cpu.usage` increases to 80-100%. |
| **Dashboard** | If you have an NDM overview dashboard, the CPU widget lights up. |

### Recommended Monitor

**Device CPU High**

```
Metric: snmp.cpu.usage
Filter: snmp_device:*
Alert: avg(last_5m) > 80%  (Warning: > 60%)
Message: "High CPU on {{snmp_device.name}} — {{value}}%"
```

---

## Scenario 5 — Interface Down (LinkDown Trap)

### What It Demonstrates

A physical interface goes down administratively or due to a link failure. Datadog receives an SNMP `linkDown` trap and shows the interface status change in NDM.

### How It Works

The script SSHs into a CSR router and issues `shutdown` on a specified interface. The CSR's SNMP agent generates a `linkDown` trap sent to the Datadog Agent.

### Simulate

```bash
# Shut down CSR1 GigabitEthernet3 (link to PAN-OS)
sudo bash /opt/ddlab/scripts/simulate-interface-down.sh down 172.20.20.10 GigabitEthernet3

# Restore it
sudo bash /opt/ddlab/scripts/simulate-interface-down.sh up 172.20.20.10 GigabitEthernet3

# Flap with 45s downtime
sudo bash /opt/ddlab/scripts/simulate-interface-down.sh flap 172.20.20.10 GigabitEthernet3 45
```

Available interfaces per router:

| Router | Interface | Peer |
|---|---|---|
| CSR1 (172.20.20.10) | GigabitEthernet2 | FRR BGP peer |
| CSR1 (172.20.20.10) | GigabitEthernet3 | CSR2 (data plane) |
| CSR1 (172.20.20.10) | GigabitEthernet4 | DD Agent (data plane) |
| CSR2 (172.20.20.11) | GigabitEthernet2 | CSR1 (data plane) |
| CSR2 (172.20.20.11) | GigabitEthernet3 | CSR3 (data plane) |
| CSR3 (172.20.20.12) | GigabitEthernet2 | CSR2 (data plane) |
| CSR3 (172.20.20.12) | GigabitEthernet3 | F5 BIG-IP |

### What to Observe in Datadog

| Where | What to Look For |
|---|---|
| **SNMP Trap Logs** (`/logs?query=source:snmp-traps`) | `linkDown` event with the interface index and name. |
| **NDM Devices → Interfaces** | Interface `ifOperStatus` changes from `up` (1) to `down` (2). The interface row turns red. |
| **NDM Topology** | The link disappears from the topology map. |
| **Network Path** | Paths traversing the down link show failure. |

### Recommended Monitor

**Interface Down (SNMP Trap)**

```
Log query: source:snmp-traps snmp_trap_name:linkDown
Alert: count(last_5m) > 0
```

**Interface Operational Status (SNMP Poll)**

```
Metric: snmp.ifOperStatus
Filter: snmp_device:* AND interface:*
Alert: avg(last_5m) != 1  (1 = up)
```

---

## Scenario 6 — Device Uptime Monitoring

### What It Demonstrates

Monitoring device uptime via SNMP `sysUpTime` to detect unexpected reboots. When a device restarts, its `sysUpTime` resets to zero, which Datadog detects as an anomalous drop.

### How It Works

This doesn't require a simulation script — Datadog NDM already polls `sysUpTimeInstance` (OID: 1.3.6.1.2.1.1.3.0) for every device. You can simulate a reboot by restarting a container:

```bash
# Restart CSR2 (simulates device reboot — sysUpTime resets)
sudo docker restart clab-ddlab-ndm-csr2

# Wait for it to come back (3-5 minutes for CSR)
sudo docker logs -f clab-ddlab-ndm-csr2 2>&1 | grep -m1 "Startup complete"
```

### What to Observe in Datadog

| Where | What to Look For |
|---|---|
| **NDM Devices → CSR2 → Overview** | `sysUpTime` resets to a small value after the reboot. The uptime graph shows a cliff. |
| **NDM Devices** | Device may briefly show as "unreachable" during reboot. |
| **SNMP Trap Logs** | `coldStart` or `warmStart` trap from the device after it reboots. |

### Recommended Monitor

**Device Reboot Detected (sysUpTime Reset)**

```
Metric: snmp.sysUpTimeInstance
Filter: snmp_device:*
Alert: change(avg(last_5m), last_5m) < -1000  (uptime decreased = reboot)
```

---

## Scenario 7 — Packet Drop Counter Increased

### What It Demonstrates

Interface discard/error counters increasing, which indicates buffer overflows, QoS drops, or CRC errors. Datadog NDM polls these counters via SNMP and can alert on sustained increases.

### How It Works

Combine packet loss injection with traffic to cause SNMP interface counters (`ifInErrors`, `ifInDiscards`, `ifOutDiscards`) to increment:

```bash
# Step 1: Inject 20% loss on CSR2
sudo bash /opt/ddlab/scripts/simulate-packet-loss.sh on csr2 20

# Step 2: Generate traffic through CSR2 (ping flood from dd-agent)
DDPID=$(sudo docker inspect clab-ddlab-ndm-dd-agent --format '{{.State.Pid}}')
sudo nsenter -n -t "$DDPID" -- ping -f -c 1000 -I eth2 10.100.3.1

# Step 3: Wait 2-3 SNMP polling intervals (~2 min)
# Step 4: Check in Datadog NDM

# Clean up:
sudo bash /opt/ddlab/scripts/simulate-packet-loss.sh off csr2
```

### What to Observe in Datadog

| Where | What to Look For |
|---|---|
| **NDM Devices → CSR2 → Interfaces** | `ifInErrors` or `ifInDiscards` counter rate increases. The interface detail page shows error/discard graphs spiking. |
| **NDM Devices → CSR2 → Overview** | Total error rate across all interfaces increases. |

### Recommended Monitor

**Interface Errors/Discards**

```
Metric: snmp.ifInErrors (rate)
Filter: snmp_device:*
Alert: avg(last_5m) > 10/sec  (Warning: > 1/sec)
```

```
Metric: snmp.ifInDiscards (rate)
Filter: snmp_device:*
Alert: avg(last_5m) > 100/sec  (Warning: > 10/sec)
```

---

## Combined Demo: Full WAN Degradation

This scenario combines multiple faults to simulate a realistic WAN outage progression. The interactive menu (option 13) runs this automatically:

```
Timeline:
  T+0s    Inject 200ms latency on CSR2 WAN links
  T+2s    Add 5% packet loss on CSR2
  T+7s    Flap CSR1 eBGP session (30s down)
  T+37s   BGP session restores
```

### Run It

```bash
# Via the interactive menu:
sudo bash /opt/ddlab/scripts/simulate-network-faults.sh
# Select option 13

# Or manually:
sudo bash /opt/ddlab/scripts/simulate-latency.sh on 200 50
sleep 2
sudo bash /opt/ddlab/scripts/simulate-packet-loss.sh on csr2 5
sleep 5
sudo bash /opt/ddlab/scripts/simulate-bgp-flap.sh 172.20.20.10 30 1
```

### What to Observe

1. **Network Path** — Latency spike on hop 2 (CSR2), packet loss increases
2. **SNMP Trap Logs** — `linkDown`, `bgpBackwardTransition`, then `linkUp`, `bgpEstablished`
3. **NDM Devices** — BGP peer state changes on CSR1, interface status flaps
4. **NDM Topology** — Link to FRR disappears during the BGP outage window

### Reset Everything

```bash
# Via menu: option 14
# Or manually:
sudo bash /opt/ddlab/scripts/simulate-latency.sh off
sudo bash /opt/ddlab/scripts/simulate-packet-loss.sh off csr2
sudo bash /opt/ddlab/scripts/simulate-cpu-stress.sh off csr
sudo bash /opt/ddlab/scripts/simulate-cpu-stress.sh off csr2
sudo bash /opt/ddlab/scripts/simulate-cpu-stress.sh off csr3
```

---

## Monitor Summary

### Recommended Datadog Monitors for NDM

| # | Monitor Name | Type | Metric / Query | Threshold | Severity |
|---|---|---|---|---|---|
| 1 | Network Path Hop Latency | Metric | `datadog.network_path.path.hop_rtt` | > 100ms (avg 5m) | P2 |
| 2 | Network Path Unreachable | Metric | `datadog.network_path.path.reachable` | < 1 (avg 5m) | P1 |
| 3 | Network Path Packet Loss | Metric | `datadog.network_path.path.packet_loss` | > 5% (avg 5m) | P2 |
| 4 | BGP Session Down (Trap) | Log | `source:snmp-traps snmp_trap_name:bgpBackwardTransition` | count > 0 (5m) | P2 |
| 5 | BGP Flapping | Log | `source:snmp-traps bgpBackwardTransition OR bgpEstablished` | count > 4 (15m) | P1 |
| 6 | BGP Peer State | Metric | `snmp.bgpPeerState` | < 6 (avg 5m) | P2 |
| 7 | Device CPU High | Metric | `snmp.cpu.usage` | > 80% (avg 5m) | P2 |
| 8 | Interface Down (Trap) | Log | `source:snmp-traps snmp_trap_name:linkDown` | count > 0 (5m) | P2 |
| 9 | Interface Oper Status | Metric | `snmp.ifOperStatus` | != 1 (avg 5m) | P3 |
| 10 | Interface Errors | Metric | `snmp.ifInErrors` (rate) | > 10/s (avg 5m) | P2 |
| 11 | Interface Discards | Metric | `snmp.ifInDiscards` (rate) | > 100/s (avg 5m) | P3 |
| 12 | Device Reboot | Metric | `snmp.sysUpTimeInstance` | change < -1000 (5m) | P1 |

---

## Datadog URLs

| View | URL |
|---|---|
| NDM Devices | https://app.datadoghq.com/devices |
| NDM Topology Map | https://app.datadoghq.com/devices/topology |
| NDM Geomap | https://app.datadoghq.com/devices/geomap |
| Network Path | https://app.datadoghq.com/network/path |
| SNMP Trap Logs | https://app.datadoghq.com/logs?query=source:snmp-traps |
| Monitors | https://app.datadoghq.com/monitors/manage |

---

## Architecture Reference

### Lab Topology

```
DD Agent (172.20.20.5)
  │ eth2: 10.99.0.1/30    ← direct data plane link
  │
  ├── SNMP poll → CSR1 (172.20.20.10)  Bangkok DC1
  ├── SNMP poll → CSR2 (172.20.20.11)  WAN Transit
  ├── SNMP poll → CSR3 (172.20.20.12)  Chiang Mai DC2
  └── SNMP poll → F5   (172.20.20.31)  Chiang Mai DC2

Network Path: Agent → CSR1 Gi4 → CSR2 Gi2 → CSR3 Lo0
                      (10.99.0.2) (10.0.12.2) (10.100.3.1)
```

### Data Plane IP Addresses

| Link | Subnet | CSR1 | CSR2 | CSR3 |
|---|---|---|---|---|
| Agent ↔ CSR1 | 10.99.0.0/30 | 10.99.0.2 (Gi4) | — | — |
| CSR1 ↔ CSR2 | 10.0.12.0/30 | 10.0.12.1 (Gi3) | 10.0.12.2 (Gi2) | — |
| CSR2 ↔ CSR3 | 10.0.23.0/30 | — | 10.0.23.1 (Gi3) | 10.0.23.2 (Gi2) |
| Loopback 0 | /32 | 10.100.1.1 | 10.100.2.1 | 10.100.3.1 |

### tc netem Interface Mapping

When injecting faults on a router container, the container's `eth` interfaces map to the CSR's GigabitEthernet interfaces:

| Container Interface | CSR Interface | Peer |
|---|---|---|
| eth1 | GigabitEthernet2 | Upstream link |
| eth2 | GigabitEthernet3 | Downstream link |
| eth3 | GigabitEthernet4 | DD Agent (CSR1 only) |

The `tc netem` rules apply at the container network namespace level, meaning they affect all traffic transiting that interface — including ICMP time-exceeded messages used by traceroute.

---

## Troubleshooting Simulations

| Issue | Fix |
|---|---|
| `tc: command not found` | Install in container: `docker exec <container> apt-get install -y iproute2` (vrnetlab containers usually have it) |
| Latency not showing in Network Path | Wait 1-2 polling intervals (60s default). Check `simulate-latency.sh status` to confirm rules are active. |
| BGP flap script hangs | CSR SSH may be slow. Increase `ConnectTimeout` or check `docker logs` for CSR readiness. |
| CPU stress doesn't raise SNMP metrics | The CSR VM may have its own CPU abstraction. Check `show processes cpu sorted` via SSH to confirm actual IOS CPU impact. |
| Packet loss simulation removed after container restart | `tc netem` rules are ephemeral — they only live in the container's network namespace. Re-apply after any `docker restart` or `containerlab deploy`. |
| `nsenter: failed to execute` | Ensure you're running as root (`sudo`) and the container PID is valid. |

For broader operational issues see [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md).

---

## Customer demo flow

Pre-flight checklist (run 5 min before the call):

```bash
# Confirm lab is healthy + on the customer's expected Datadog org
gcloud compute ssh labuser@ddlab-ndm --zone=asia-southeast1-a \
  --project=<your-proj> --tunnel-through-iap --command='
sudo docker ps --format "{{.Names}}\t{{.Status}}" | grep clab-ddlab-ndm
sudo docker exec clab-ddlab-ndm-dd-agent agent status 2>&1 \
  | sed "s/\x1b\[[0-9;]*m//g" | grep -cE "snmp:.*\[(OK|WARNING)\]" \
  | xargs -I N echo "SNMP OK: N of 5"
sudo docker exec clab-ddlab-ndm-dd-agent agent status 2>&1 \
  | sed "s/\x1b\[[0-9;]*m//g" | grep -c "network_path:.*\[OK\]" \
  | xargs -I N echo "NetworkPath OK: N of 8"
sudo bash /opt/ddlab/scripts/simulate-latency.sh off 2>/dev/null || true
sudo bash /opt/ddlab/scripts/simulate-packet-loss.sh off csr2 2>/dev/null || true
'
```

Open these tabs ahead of the call:

1. NDM device list — filter `device_namespace:lab-th`
2. Open CSR2 (`172.20.20.11`) device detail page
3. NetworkPath — filter `path_type:data-plane`
4. Open the path `agent-to-cnx-endpoint` (5-hop) detail view

### 30-min demo agenda

| Time | Section | What to do | What to say |
|---|---|---|---|
| 0:00 | Intro the topology (slide or whiteboard) | Show the BKK → Transit → CNX 5-CSR diagram from `README.md` | "This represents your prod WAN at small scale. Same agent, same SNMP profiles, same UI as you'd see in production." |
| 0:05 | NDM fleet view | Tab 1 — point at the 5 device rows | "All polled via SNMPv3 every 15 s. CPU, mem, interface counters, BGP, CDP topology — all standard." |
| 0:08 | NDM device drill-down | Tab 2 — click CSR2 → interfaces, BGP table | "Click any device, you get this view. Notice the dynamic device tags — `site`, `team`, `role` — these are tags YOU control via SNMP config." |
| 0:12 | NetworkPath baseline | Tab 3 + 4 — show 5-hop path, all green ~1-3 ms | "This is the bit you don't get from SolarWinds. Every probe is recorded as time-series. We can chart hop-2 RTT over the last 30 days, alert when it changes, correlate with anything else in Datadog." |
| 0:15 | **Demo Scenario 1** (latency) | `sudo bash /opt/ddlab/scripts/simulate-latency.sh on 200 50` | "Imagine someone misconfigures QoS on a transit router…" |
| 0:17 | Watch hop 2 light up | Refresh path view, point at hop-2 RTT going from 1 ms → 200 ms; baseline path (hop 1, csr1) stays clean | "Notice we IMMEDIATELY know it's hop 2 — not just 'the path is slow'. Saves 30+ min of `traceroute` from a jumphost." |
| 0:22 | Show monitor | Open the recommended `network_path_hop_rtt` monitor | "And we can alert on a per-hop basis." |
| 0:25 | Cleanup + Q&A | `sudo bash /opt/ddlab/scripts/simulate-latency.sh off` | |

### 60-min demo agenda

Same as 30-min, plus:

| Time | Add | Run |
|---|---|---|
| 0:30 | Scenario 2: packet loss | `simulate-packet-loss.sh on csr2 30` |
| 0:38 | Scenario 4: interface flap | `simulate-interface-down.sh on csr2 eth1 30` |
| 0:46 | Scenario 6: full WAN degradation | `simulate-network-faults.sh` → menu option for "full degradation" |
| 0:54 | SNMP traps demo | Trigger BGP shutdown — show `source:snmp-traps` log appearing in real time |

### Resetting between runs

```bash
# One-shot: nuke all simulated faults
sudo bash /opt/ddlab/scripts/simulate-network-faults.sh
# choose: 99) Reset everything
```

Or:

```bash
sudo bash /opt/ddlab/scripts/simulate-latency.sh     off
sudo bash /opt/ddlab/scripts/simulate-packet-loss.sh off csr   2>/dev/null || true
sudo bash /opt/ddlab/scripts/simulate-packet-loss.sh off csr2  2>/dev/null || true
sudo bash /opt/ddlab/scripts/simulate-packet-loss.sh off csr3  2>/dev/null || true
sudo bash /opt/ddlab/scripts/simulate-cpu-stress.sh  off csr2  2>/dev/null || true
```

### Building dashboards for the demo

Two pre-built dashboards customers love seeing:

1. **"WAN Health Single Pane"** — combine these widgets:
   - Top: NDM fleet status table (group by `site`, count `OK / WARNING / ERROR`)
   - Middle: NetworkPath RTT timeseries `avg:datadog.network_path.path.hop_rtt{path_type:data-plane} by {path_name}`
   - Bottom-left: NetworkPath reachability heatmap by destination
   - Bottom-right: SNMP trap stream `source:snmp-traps`
   - Overlay: Datadog events tagged `source:netops-runbook` for change windows

2. **"Per-device deep-dive"** — pick a CSR, show:
   - Top widgets: CPU, memory, BGP peer state from `snmp.*` metrics
   - Middle: interface throughput per `interface` tag
   - Bottom: NetworkPath paths whose hops include this device's interfaces

Both dashboards can be exported as JSON and shipped to the customer for their own use — the metric/tag model is identical between this lab and production.

---

## Further reading

- [Datadog Network Monitoring](https://docs.datadoghq.com/network_monitoring/) (top-level)
- [NDM overview](https://docs.datadoghq.com/network_monitoring/devices/) + [setup](https://docs.datadoghq.com/network_monitoring/devices/setup/)
- [SNMP profiles](https://docs.datadoghq.com/network_monitoring/devices/profiles/) + [profile authoring](https://docs.datadoghq.com/network_monitoring/devices/profile_format/)
- [NetworkPath](https://docs.datadoghq.com/network_monitoring/network_path/) + [setup](https://docs.datadoghq.com/network_monitoring/network_path/setup/)
- [SNMP traps](https://docs.datadoghq.com/network_monitoring/devices/snmp_traps/) and [NetFlow](https://docs.datadoghq.com/network_monitoring/devices/netflow/)
- [Topology Map (CDP/LLDP)](https://docs.datadoghq.com/network_monitoring/devices/topology_map/)
- [Cloud Network Monitoring](https://docs.datadoghq.com/network_monitoring/cloud_network_monitoring/) — adjacent product for cloud flow telemetry
- [Datadog Agent SNMP integration source](https://github.com/DataDog/integrations-core/tree/master/snmp) — bundled profiles + Python check source
- [`README.md`](README.md) — lab setup, integration snippets you can lift to production
- [`TROUBLESHOOTING.md`](TROUBLESHOOTING.md) — operational gotchas
