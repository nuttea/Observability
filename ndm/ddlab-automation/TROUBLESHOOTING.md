# Troubleshooting Playbook

All commands assume you are SSH'd into the GCE VM:

```bash
gcloud compute ssh labuser@ddlab-ndm \
  --zone=asia-southeast1-a \
  --project=<your-project> \
  --tunnel-through-iap
```

The dd-agent container is `clab-ddlab-ndm-dd-agent`; the 5 CSRs are `clab-ddlab-ndm-csr`, `-csr2`, `-csr3`, `-csr4`, `-csr5`.

---

## Quick health check

```bash
# 1) All containers healthy?
sudo docker ps --format 'table {{.Names}}\t{{.Status}}' | grep clab-ddlab-ndm

# 2) Agent data-plane uplink (eth2) still attached?
sudo docker exec clab-ddlab-ndm-dd-agent ip -br addr show eth2
# want: eth2@ifXXX  UP  10.99.0.2/30  ...

# 3) Host route that feeds system-probe traceroute?
ip route | grep 10.0.0.0
# want: 10.0.0.0/8 via 172.20.20.5 dev br-XXX

# 4) SNMP instance state
sudo docker exec clab-ddlab-ndm-dd-agent agent status 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'Instance ID: snmp:'
# want: 5 instances, IDs starting with `snmp:lab-th:172.20.20.` (core loader),
#       all [OK] or [WARNING]

# 5) NetworkPath instance state
sudo docker exec clab-ddlab-ndm-dd-agent agent status 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep 'network_path:'
# want: 8 instances, all [OK]

# 6) Sanity: can the agent walk the 5-hop chain?
sudo docker exec clab-ddlab-ndm-dd-agent traceroute -n -I -w 2 -m 8 csr5-cnx-endpoint
# want: 5 hops ending at 10.100.5.1
```

If all six checks pass, the lab is fully healthy.

---

## Scenario 1 — NetworkPath data-plane paths at 0-40% reachability

**Symptom:** Only the `-mgmt` NetworkPath traces stay at 100%. The five data-plane traces (`csr1-bkk-edge`, `csr2-wan-transit`, …, `csr5-cnx-endpoint`) drop to ~0-40%.

**Root cause:** The clab-managed veth pair between `dd-agent:eth2` and `csr:Gi4` got destroyed. This happens whenever someone runs `docker restart clab-ddlab-ndm-dd-agent` — the container filesystem survives but the kernel veth peer is gone. The `clab exec:` hook only runs on fresh deploy, not on restart.

**Diagnose:**

```bash
sudo docker exec clab-ddlab-ndm-dd-agent ip -br addr show eth2
# "Device eth2 does not exist." confirms it
```

**Fix — just re-run `deploy-lab.sh`:**

```bash
sudo bash /opt/ddlab/scripts/deploy-lab.sh
```

It's **idempotent and self-healing** as of the current revision:

1. Detects missing CSR containers via `docker ps`
2. Cleans any stale clab state on disk
3. Pre-seeds the SNMP profile before deploying
4. Redeploys the topology (reattaches eth2 veth)
5. Waits for CSRs to boot (~5-7 min for 5 CSRs in parallel)
6. Post-deploy fixes (host route, MASQUERADE, /etc/hosts, validate)

**Prevention:** Never `docker restart` a clab-managed container. To reload agent config without losing eth2, use `docker kill -s HUP clab-ddlab-ndm-dd-agent` — SIGHUP doesn't tear the container down.

---

## Scenario 2 — NDM UI shows fewer than 5 devices

> **Note:** With the current scripts (`deploy-lab.sh` pre-seeds the profile **before** the agent starts), this is rare. If you see this, the most likely cause is an older revision of the config still on disk, or someone ran `docker restart` on the agent without re-deploying the lab.

**Symptoms you might see:**

| Symptom | Likely cause |
|---|---|
| 3 CSRs visible, 2 missing | Old Python-loader config lingering — the pysnmp `no current event loop` bug drops the 4th+ instance silently |
| 0 CSRs visible | Core loader can't find the `cisco-csr1000v` profile (user profile dir empty) |
| 5 visible only for ~24 h, then 2-3 go stale | One of the above — the stale devices are the ones that *were* polling before the regression |

**Diagnose:**

```bash
# Check instance ID format:
#   core loader:   "snmp:lab-th:172.20.20.10:<hash>"    ← expected
#   python loader: "snmp:<hash>"                        ← wrong
sudo docker exec clab-ddlab-ndm-dd-agent agent status 2>&1 \
  | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'Instance ID: snmp:'

# Common errors
sudo docker exec clab-ddlab-ndm-dd-agent bash -c \
  "grep -E 'unknown profile|var_binds|no current event loop' /var/log/datadog/agent.log | tail"
```

**Fix:** just re-run `deploy-lab.sh` — it's idempotent and does everything in the right order (pre-seed profile, redeploy if CSRs missing, reinstall tools, repopulate hosts):

```bash
sudo bash /opt/ddlab/scripts/deploy-lab.sh
```

If that somehow doesn't resolve it, check:

```bash
# (a) Is autodiscovery accidentally enabled? (it shouldn't be)
sudo grep -A 2 '^  autodiscovery:' /opt/ddlab/datadog.yaml   # want: enabled: false

# (b) Is instances.yaml using the core loader?
sudo grep -E 'loader:|profile:' /opt/ddlab/conf.d/snmp.d/instances.yaml
# Want all 5 instances with `loader: core` + `profile: cisco-csr1000v`

# (c) Last-resort nuke: full destroy + apply from Terraform (see Scenario 11)
```

**Why the Python loader is not used:** `pysnmp` calls `asyncio.get_event_loop()` from a worker thread that doesn't have one initialized. The first 2-3 instances succeed (the main thread has an event loop); the 4th+ fail to instantiate and silently drop metric collection while still showing `[OK]` in `agent status`. Only the first 3 devices ever appear in NDM. The lab explicitly forces `loader: core` to sidestep this.

---

## Scenario 3 — `unknown profile "cisco-csr1000v"` in agent log

The core loader can't find the profile file on disk.

```bash
# Verify the profile is in the user profile dir
sudo ls /opt/ddlab/conf.d/snmp.d/profiles/ | head

# If empty or missing cisco-csr1000v.yaml, reinstall
sudo bash /opt/ddlab/scripts/install-csr1000v-profile.sh

# Then SIGHUP (do NOT restart — keeps eth2 intact)
sudo docker kill -s HUP clab-ddlab-ndm-dd-agent
```

---

## Scenario 4 — `ConfigurationError: Profile X has the same sysObjectID as Y`

Two profile files in the user dir claim the same sysObjectID. This happens if a previous version of the template wrote `paloalto-panos.yaml` or `cisco-csr-bgp.yaml` that now conflict with the bundled ones.

**Fix:**

```bash
# Nuke any user profiles that aren't needed, then reinstall just CSR1000v
sudo rm -f /opt/ddlab/conf.d/snmp.d/profiles/*.yaml
sudo bash /opt/ddlab/scripts/install-csr1000v-profile.sh
sudo docker kill -s HUP clab-ddlab-ndm-dd-agent
```

---

## Scenario 5 — Load test aborts with "hping3: not found"

The dd-agent image doesn't ship with hping3; it's installed by the `clab exec:` hook at deploy. If the container filesystem was reset (e.g. by a redeploy), `hping3` is gone.

```bash
sudo docker exec clab-ddlab-ndm-dd-agent bash -c \
  "apt-get -qq update && apt-get -qq install -y hping3 traceroute iputils-ping curl snmp"
```

---

## Scenario 6 — Traceroute loops between two routers

Example:

```
4  10.0.23.1  ...
5  10.0.23.2  ...
6  10.0.23.1  ...
7  10.0.23.2  ...
```

This is an iBGP convergence gap — a router has a default route back upstream, and the hop that it should forward to hasn't yet propagated a learned prefix. The lab's CSR configs carry belt-and-suspenders static routes that cover this, but they can still flap for the first ~2-3 minutes after a cold boot.

**Fix:** wait 3 minutes and retry the traceroute. If it still loops after 5 minutes, the static routes didn't render correctly — rerun `deploy-lab.sh`.

---

## Scenario 7 — `deploy-lab.sh` or `containerlab deploy` says "lab already deployed"

Stale clab state from an interrupted earlier run.

```bash
sudo containerlab destroy --topo /opt/ddlab/containerlab/ndm-lab.clab.yml --cleanup
# If clab says "no containerlab containers found" but deploy still errors:
sudo docker ps -a --filter label=containerlab=ddlab-ndm -q | xargs -r sudo docker rm -f
sudo rm -rf /opt/ddlab/containerlab/clab-ddlab-ndm
sudo bash /opt/ddlab/scripts/deploy-lab.sh
```

---

## Scenario 8 — Startup script skips (`Bootstrap lock exists`)

If you need to re-render the on-VM configs (e.g., after editing `startup.sh.tpl` and running `terraform apply`), you must remove the idempotency lock first:

```bash
sudo rm -f /var/run/ddlab-bootstrap.lock
sudo systemctl reset-failed ddlab-rerun.service 2>/dev/null || true
sudo truncate -s 0 /var/log/ddlab-startup.log
sudo systemd-run --unit=ddlab-rerun \
  --description="Re-render configs" \
  /usr/bin/google_metadata_script_runner startup

# Watch progress
sudo tail -f /var/log/ddlab-startup.log
# STAGE 1..STAGE 12 should run. Stop watching when "STAGE 12" appears.

# Then redeploy the lab to pick up topology / CSR-startup changes
sudo bash /opt/ddlab/scripts/deploy-lab.sh
```

If stage 4 fails with `fatal: detected dubious ownership in repository at '/opt/vrnetlab'`, run:

```bash
sudo git config --system --add safe.directory /opt/vrnetlab
sudo git config --global --add safe.directory /opt/vrnetlab
# Then re-run the startup script above.
```

---

## Scenario 9 — `gcloud` auth expired during a long session

If terminal commands start failing with `gcloud.compute.ssh: There was a problem refreshing your current auth tokens: Reauthentication failed`, re-run:

```bash
gcloud auth login
```

Then resume — nothing on the VM is lost, only the local gcloud CLI credentials need refreshing.

---

## Scenario 10 — CSR1000v VM won't boot / never reaches `CVAC-4-CONFIG_DONE`

Check the QEMU serial log:

```bash
sudo docker logs clab-ddlab-ndm-csr4 2>&1 | tail -40
```

Common causes:

- **Not enough RAM on the GCE host.** 5 CSRs × 4 GB = 20 GB + Docker/agent overhead. `free -h` should show ~8-10 GB free. If not, upgrade `machine_type` to `n2-standard-16` in `terraform.tfvars` and `terraform apply` (will replace the VM).
- **Nested KVM not enabled.** Verify `/dev/kvm` exists and `kvm-ok` reports OK:

  ```bash
  ls -l /dev/kvm
  kvm-ok
  ```

- **qcow2 file missing or corrupt.** Rebuild:

  ```bash
  sudo rm -rf /opt/vrnetlab/csr/docker/*
  ls -l /opt/vrnetlab/csr/*.qcow2
  sudo bash /opt/ddlab/scripts/build-images.sh
  ```

---

## Useful one-liners

```bash
# Tail the agent log for SNMP issues
sudo docker exec clab-ddlab-ndm-dd-agent tail -f /var/log/datadog/agent.log | grep -i snmp

# Full containerlab inspect
sudo containerlab inspect --topo /opt/ddlab/containerlab/ndm-lab.clab.yml

# Console into a CSR (Ctrl-] then type "quit" to exit)
sudo docker exec -it clab-ddlab-ndm-csr3 telnet localhost 5000

# Snapshot RAM usage by container
sudo docker stats --no-stream --format 'table {{.Name}}\t{{.MemUsage}}' | grep clab-ddlab

# Quick traceroute matrix (paste into a shell inside the agent)
for d in csr1-bkk-edge csr2-wan-transit csr3-cnx-edge csr4-cnx-access csr5-cnx-endpoint; do
  printf '%-25s ' "$d"
  traceroute -n -I -w 2 -m 8 "$d" 2>&1 | tail -1
done
```

---

## Scenario 11 — `terraform destroy` fails with "bucket containing objects"

**Symptom:**

```
Error: Error trying to delete bucket <project>-<lab>-cache
       containing objects without `force_destroy` set to true
```

**This is by design** — not an error. The bucket caches the ~2 GB CSR1000v qcow2 + built vrnetlab image. Preserving it across `terraform destroy` saves ~15 min on every subsequent `apply`.

**What actually happened:**

- Terraform destroyed the VM, VPC, NAT, firewalls, and IAM binding successfully
- Terraform tried to destroy the bucket
- GCP refused because `force_destroy = false` (our default) and the bucket has objects
- Exit code 1, but everything else was cleaned up

**What to do:**

```bash
# Almost always what you want — leave the cache alone
terraform apply     # Recreate VM etc. Startup uses the cached image.

# If you really want to wipe the cache too (will need to re-upload qcow2)
terraform destroy -var image_cache_force_destroy=true

# Or: empty the bucket manually, then destroy
gsutil rm -r gs://<project>-<lab>-cache/
terraform destroy
```

---

## When all else fails: nuke from orbit

If VM state is deeply corrupted, the cleanest reset is to destroy and re-apply. **The cache bucket will survive**, so the re-apply will auto-deploy the lab without needing to rebuild anything:

```bash
cd ndm/ddlab-automation/terraform
set -a && source .env && set +a && export TF_VAR_dd_api_key="$DD_API_KEY"

terraform destroy -auto-approve   # expect one error on the bucket — that's fine
terraform apply   -auto-approve   # ~75 s to return
# Then wait ~10 min — startup script auto-deploys everything.
# Monitor:
gcloud compute ssh labuser@$(terraform output -raw instance_name) \
  --zone=$(terraform output -raw instance_zone) \
  --project=$(terraform console <<<'var.gcp_project' | tr -d '"') \
  --tunnel-through-iap -- 'tail -f /var/log/ddlab-deploy.log'
```

Proven end-to-end timing (smoke-tested): **~12 min** from `terraform destroy` to a fully working 5-CSR lab.

If the cache bucket itself is corrupted (very rare — e.g. an accidentally uploaded bad qcow2):

```bash
# Full wipe including cache
terraform destroy -var image_cache_force_destroy=true
# Then follow the first-time setup in README.md (needs re-uploading the qcow2)
```
