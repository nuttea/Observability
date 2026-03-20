---
name: datadog-healthcheck
description: Perform comprehensive Datadog account health checks analyzing infrastructure, monitors, logs, services, SLOs, and dashboards. Produce scored reports (out of 100) with findings and actionable recommendations. Use when the user asks to analyze Datadog health, check account configuration, run a health check, identify configuration issues, get Datadog best-practice recommendations, or mentions "health check", "account analysis", or "optimization".
---

# Datadog Account Health Check

Perform a professional-grade Datadog account health check using MCP tools. Produce a scored report with findings and prioritized recommendations.

## MCP Tools Used

- Infrastructure: `list_hosts`, `get_active_hosts_count`
- Monitors: `get_monitors`
- Logs: `get_logs`, `get_all_services`
- SLOs: `list_slos`, `get_slo`, `get_slo_history`
- APM: `get_service_stats_realtime`, `get_service_endpoints`, `get_operation_stats`
- Dashboards: `list_dashboards`

## Health Check Workflow

### Step 1: Infrastructure Health (25 points)

Assess host coverage, agent deployment, and tagging compliance.

1. Call `list_hosts` with `include_hosts_metadata: true`
2. Count total hosts, hosts with agent vs cloud-only, hosts with `env` tag, hosts with `team` tag
3. Calculate percentages and score:
   - Agent coverage >90%: 10/10
   - Env tag coverage >85%: 8/8
   - Team tag coverage >75%: 7/7

### Step 2: Monitor Quality (25 points)

Identify alert fatigue, coverage gaps, and routing issues.

1. Call `get_monitors` to get all monitors
2. For each monitor, check tags for priority (P1-P5), team ownership, environment
3. Use `get_logs` with query `@evt.name:monitor.triggered` to estimate trigger frequency
4. Score:
   - Alert fatigue <5% high-frequency monitors: 10/10
   - Priority tags >90%: 10/10
   - Coverage adequate: 5/5

Flag monitors triggering >15 times/week as alert fatigue candidates. List top offenders with estimated trigger counts.

### Step 3: Log Efficiency (20 points)

Optimize log indexing, parsing, and costs.

1. Call `get_logs` with query `*` (limit: 1000) to sample logs
2. Call `get_all_services` for service list
3. Analyze sample: status distribution (debug/info/warn/error), services with/without proper tags, DEBUG percentage
4. Score:
   - Pipeline coverage estimated >70%: 8/8
   - DEBUG <10%: 7/7
   - Tag coverage >90%: 5/5

Estimate cost impact of DEBUG logs (percentage of volume, potential monthly savings if excluded).

### Step 4: SLO & Service Performance (20 points)

Analyze SLO coverage, service performance, and error budgets.

1. Call `get_all_services` to list all services
2. For each service: call `get_service_stats_realtime` (request rate, error rate, latency) and `get_service_endpoints` (top endpoints)
3. Call `list_slos` to get all SLOs
4. Compare service list vs SLO coverage
5. Score:
   - SLO coverage for critical services: 10/10
   - All SLOs above target: 5/5
   - Error budgets >20%: 5/5

List services needing SLOs (prioritize by error rate and traffic).

### Step 5: Dashboard Health (10 points)

Identify stale dashboards and organization.

1. Call `list_dashboards`
2. Check dashboards without tags, naming conventions
3. Score:
   - Tag coverage >80%: 5/5
   - Organization: 5/5

## Report Generation

See [references/report-template.md](references/report-template.md) for the full output template.

### Calculate Overall Score

Sum all section scores (total: 100 points).

### Health Status

- **90-100**: Excellent
- **75-89**: Good
- **60-74**: Needs Improvement
- **<60**: Action Required

### Prioritize Action Items

**HIGH Priority** (implement within 1 week):
- Scores <15 in any section
- Security/compliance issues
- Cost optimization >$500/month
- Critical service issues (>5% error rate)

**MEDIUM Priority** (implement within 1 month):
- Scores 15-20 in any section
- Efficiency improvements, tag coverage gaps, monitor optimization

**LOW Priority** (nice-to-have):
- Scores >20 in any section
- Minor optimizations, best practice enhancements

### Focused Analysis

If the user requests analysis of specific sections only (e.g., "check just my monitors"), skip irrelevant steps and provide targeted recommendations for the requested areas.

### Report Output

Save report as markdown. Default filename: `healthcheck-YYYYMMDD.md`. Include:
- Executive summary with key highlights
- Detailed scores table (category, score, status, notes)
- Priority action items (HIGH/MEDIUM/LOW)
- Cost optimization opportunities with estimated savings
- Detailed findings from each step
