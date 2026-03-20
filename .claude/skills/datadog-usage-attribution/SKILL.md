---
name: datadog-usage-attribution
description: Analyze Datadog usage and costs, recommend optimal tags for usage attribution and chargeback. Identify which teams, services, or environments consume most resources. Use when the user asks about Datadog costs, usage attribution, chargeback setup, cost allocation, spending by team/service/environment, cost optimization, or asks "which tags should I use for billing". Also use when user mentions "showback", "cost center", or "usage analysis".
---

# Datadog Usage Attribution Analysis

Analyze Datadog usage patterns and recommend optimal tags for cost allocation, chargeback, and usage attribution.

**Key constraint**: Datadog allows only **3 custom tag keys** for usage attribution. Choosing the right 3 is critical.

## MCP Tools Used

- Infrastructure: `list_hosts`
- Services: `get_all_services`, `get_service_stats_realtime`
- Monitors: `get_monitors`
- Logs: `get_logs`
- Metrics: `query_metrics`

## Analysis Workflow

### Step 1: Discover Current Tag Usage

1. Call `list_hosts` -- extract all unique tags and calculate tag prevalence
2. Call `get_all_services` -- extract service tags
3. Call `get_monitors` -- extract monitor tags
4. Calculate per-tag: resource count, coverage percentage, unique values, cardinality level

### Step 2: Query Current Usage Metrics

Call `query_metrics` for Datadog estimated usage metrics, grouped by available tags:

- `sum:datadog.estimated_usage.hosts{*} by {team}` -- infrastructure by team
- `sum:datadog.estimated_usage.apm.hosts{*} by {service,env}` -- APM by service/env
- `sum:datadog.estimated_usage.logs.ingested_bytes{*} by {team,env}` -- logs by team/env
- `sum:datadog.estimated_usage.metrics.custom{*} by {*}` -- custom metrics

Use 30-day window. Identify what percentage of usage has "no tag" (unattributed).

### Step 3: Analyze Resource Consumption Patterns

Combine metrics data with resource inventory:

1. **Infrastructure**: Count hosts per tag value (more hosts = higher cost)
2. **APM**: Get service stats for request volumes (more requests = higher cost)
3. **Logs**: Sample logs and count by service/team (more volume = higher cost)

Produce estimated usage distribution tables by each candidate tag (team, env, service, application, etc.).

### Step 4: Recommend Optimal 3 Tags

Score each tag candidate using these criteria (see [references/tag-recommendation-framework.md](references/tag-recommendation-framework.md) for details):

1. **Coverage** (30%): >80% of resources tagged
2. **Cardinality** (20%): <50 unique values
3. **Business alignment** (30%): Maps to cost centers, teams, or products
4. **Actionability** (20%): Can take action based on insights

Present top 3 recommended tag combinations with rationale. Provide 2-3 options for different scenarios (team chargeback, project-based, service-first).

### Step 5: Pre-Implementation Readiness Check

For chosen tags, verify:
- Coverage is sufficient (>80%)
- Values are standardized (lowercase, consistent)
- Tag keys exist across products (infra, APM, logs)

List resources without chosen tags. Estimate "unattributed" cost percentage.

### Step 6: Usage Pattern Analysis

Identify cost optimization opportunities:
- Staging over-provisioning (if stage >25% of total cost)
- High-log-volume services
- Unused/idle hosts
- Team resource imbalance

Estimate potential monthly savings for each opportunity.

## Report Generation

See [references/report-template.md](references/report-template.md) for the full output template. Include:
- Executive summary with recommended 3 tags and expected benefit
- Tag analysis with scoring for each candidate
- Estimated usage distribution by tag
- Readiness assessment with blockers
- Implementation roadmap (4-week plan)
- Cost optimization opportunities with estimated savings

## Implementation Steps

See [references/implementation-guide.md](references/implementation-guide.md) for detailed steps covering:
- Tag preparation and gap remediation
- Configuring usage attribution in Datadog UI
- Post-implementation validation
- Cost dashboard creation
- Monitoring attribution quality over time
