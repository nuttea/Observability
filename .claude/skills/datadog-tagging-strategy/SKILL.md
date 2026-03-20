---
name: datadog-tagging-strategy
description: Analyze Datadog tagging compliance and coverage across infrastructure, services, monitors, logs, dashboards, and SLOs. Check adherence to tagging standards (env, team, tier, etc.), identify gaps, tag value violations, high-cardinality tags, and recommend improvements. Use when the user asks about tagging strategy, tag coverage, tag compliance, tag audit, missing tags, tagging best practices, Unified Service Tagging (UST), or wants to identify untagged resources.
---

# Datadog Tagging Strategy Analysis

Analyze Datadog tagging compliance and provide actionable recommendations. Refer to [references/tagging-framework.md](references/tagging-framework.md) for the complete tag definitions, targets, and scoring system.

## MCP Tools Used

- Infrastructure: `list_hosts` (with `include_hosts_metadata: true`)
- Services: `get_all_services`, `list_traces`, `get_service_stats_realtime`
- Monitors: `get_monitors`
- Logs: `get_logs`
- Dashboards/SLOs: `list_dashboards`, `list_slos`

## Analysis Workflow

### Step 1: Infrastructure Tag Audit (40 points)

1. Call `list_hosts` with `include_hosts_metadata: true`
2. For each host, check presence of: `env` (reserved), `host` (reserved), `team` (critical), `tier`, `role`, `datacenter`, `platform` (recommended)
3. Calculate coverage percentages per tag
4. Identify violations: hosts without env/team, hosts with invalid env values (not in [dev, stage, prod])
5. Score: env tag (20 pts), team tag (15 pts), tier tag (5 pts)

### Step 2: Service (APM) Tag Audit (30 points)

1. Call `get_all_services` to discover services
2. For each service, call `list_traces` to sample span tags
3. Check Unified Service Tagging (UST) compliance: `service` + `env` + `version` = Complete UST
4. Also check: `team`, `runtime`, `journey` tags
5. Score: UST complete (20 pts), team tag (10 pts)

### Step 3: Monitor Tag Compliance (20 points)

1. Call `get_monitors` to get all monitors
2. Check required tags: `service`, `env`. Check critical tags: `team` (for routing), `priority` (P1-P5)
3. Check tag format: lowercase compliance, no CamelCase, key:value format
4. Score: team tag (10 pts), priority tag (10 pts)

### Step 4: Log Tag Coverage

1. Call `get_logs` with query `*` (sample 1000-5000 logs from past week)
2. Check each log for: `service` (critical for APM correlation), `source` (critical for parsing), `host`, `status`
3. Calculate coverage from sample

### Step 5: Dashboard & SLO Tag Organization

1. Call `list_dashboards` and `list_slos`
2. Check for tag presence on each
3. Dashboards/SLOs without tags are hard to discover and filter

### Step 6: Tag Value Standardization

Collect all unique tag values across resources and check for:
- CamelCase violations (should be lowercase)
- Inconsistent values (e.g., dev vs development vs DEV)
- Special characters (converted to underscores)
- Unbounded/high-cardinality tags (timestamps, UUIDs, user_ids) -- flag tags with >1000 unique values

## Report Generation

See [references/report-template.md](references/report-template.md) for the full output template. Include:
- Overall compliance score (out of 100) with status
- Per-category breakdown (Infrastructure, APM, Monitors, Logs, Dashboards)
- Priority action items (HIGH/MEDIUM/LOW)
- Specific resources missing critical tags
- Tag format violations with corrections
- High-cardinality tag warnings

## Remediation Guidance

See [references/remediation-guide.md](references/remediation-guide.md) for implementation instructions covering:
- Infrastructure host tagging (datadog.yaml, cloud tags)
- APM Unified Service Tagging (DD_ENV, DD_SERVICE, DD_VERSION)
- Monitor tag additions
- Log collection tag configuration
- Automation recommendations (tag policy as code, CI/CD validation)
