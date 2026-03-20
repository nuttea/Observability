---
name: datadog-usage-analysis
description: Analyze Datadog org usage vs. committed/purchased SKU amounts. Query live metrics via Datadog MCP, compute allotments and overages, and produce a structured comparison report. Use when the user asks to check Datadog usage, compare usage to commitments, estimate overages, analyze billing, check cost, or mentions "usage analysis", "usage vs committed", "overage", "allotment", or "Plan & Usage".
---

# Datadog Usage Analysis

Analyze a Datadog org's actual usage against committed/purchased product amounts, identify overages and allotment breaches, and produce an actionable comparison report.

## Prerequisites

- **Datadog MCP** tools available (get_datadog_metric, get_datadog_metric_context, search_datadog_metrics, analyze_datadog_logs, search_datadog_rum_events)
- User must provide (or you must ask for) their **committed SKUs and amounts**

## Workflow

### Phase 1: Gather Committed Amounts

Ask the user for their purchased/committed products and quantities. Use the AskQuestion tool or ask conversationally. Collect ALL that apply:

**Infrastructure:**
- Infra tier (Pro / Pro Plus / Enterprise) + host count
- APM tier (Pro / Enterprise) + host count

**Logs:**
- Logs Ingest commitment (GB/month)
- Logs Index — per retention tier: how many events/month at which retention (3d, 7d, 15d, 30d, 45d, 60d)
- Flex Logs Starter — events/month into Flex + retention length (3, 6, 12, or 15 months)
- Flex Logs Scalable — stored events + compute tier (if applicable)

**RUM (three separate SKUs):**
- RUM Measure — sessions/month
- RUM Investigate — sessions/month
- Session Replay — sessions/month

**Other products (if applicable):**
- Custom Metrics, Serverless (Lambda functions, invocations, Fargate tasks, Serverless Apps instances), Synthetics (API runs, Browser runs), Profiler hosts, DBM hosts, USM hosts, NPM hosts, NDM devices, CSPM/CWS/ASM hosts, Cloud SIEM bytes, SDS bytes, CI Visibility committers

### Phase 2: Determine Timeframe

Default: **current month-to-date** (1st of current month → today).
Ask user if they want a different period. Use ISO 8601 for `from`/`to` parameters.

### Phase 3: Query Actual Usage

Use Datadog MCP tools to fetch each committed product's usage. See [metrics-reference.md](metrics-reference.md) for the full metric catalog.

**Critical: gauge vs count metric types**

| Metric type | Products | How to query |
|-------------|----------|-------------|
| **Gauge** | Infra hosts, APM hosts, containers, custom metrics, profiler, DBM, USM, NPM, CSPM, CWS, ASM | `sum:datadog.estimated_usage.X{*}` — read avg/max directly, do NOT sum over time |
| **Count** | Logs events/bytes, RUM sessions, APM spans, Synthetics runs | Must use `.as_count()` and sum/rollup over time |

**Query checklist by product:**

```
# GAUGE metrics — use get_datadog_metric, read avg/max from binned response
sum:datadog.estimated_usage.hosts{*}
sum:datadog.estimated_usage.apm_hosts{*}
sum:datadog.estimated_usage.containers{*}
sum:datadog.estimated_usage.metrics.custom{*}
sum:datadog.estimated_usage.profiling.hosts{*}
sum:datadog.estimated_usage.profiling.containers{*}
sum:datadog.estimated_usage.dbm.hosts{*}
sum:datadog.estimated_usage.network.hosts{*}

# COUNT metrics — use get_datadog_metric with raw_data:true, sum all values
sum:datadog.estimated_usage.logs.ingested_bytes{*}.as_count()
sum:datadog.estimated_usage.logs.ingested_events{datadog_is_excluded:false}.as_count()
sum:datadog.estimated_usage.logs.ingested_events{datadog_is_excluded:false} by {datadog_index}.as_count()
sum:datadog.estimated_usage.rum.ingested_sessions{*}.as_count()
sum:datadog.estimated_usage.rum.indexed_sessions{*}.as_count()
sum:datadog.estimated_usage.rum.sessions{sku:replay}.as_count()
sum:datadog.estimated_usage.apm.indexed_spans{*}.as_count()
sum:datadog.estimated_usage.apm.ingested_bytes{*}.as_count()
```

**Flex Logs:** No EUM metric exists. Note this in the report and instruct user to check [Plan & Usage → Logs](https://app.datadoghq.com/billing/usage?category=logs) for "Flex Logs Stored (Starter)".

### Phase 4: Compute Allotments

Using the committed amounts AND actual host counts, calculate allotments per [metrics-reference.md](metrics-reference.md) allotment tables.

**Key allotment formulas:**

```
Container allotment = max(actual_hosts, committed_hosts) × containers_per_host
  Infra Pro/Pro Plus: 5 containers/host
  Infra Enterprise:   10 containers/host
Container overage = max(0, actual_containers - container_allotment)
Container overage cost = overage × $0.002/container/hour

Custom metrics allotment = max(actual_hosts, committed_hosts) × metrics_per_host
  Infra Pro/Pro Plus: 100/host
  Infra Enterprise:   200/host

APM indexed spans allotment = max(actual_apm_hosts, committed_apm_hosts) × 1M spans/host/month
APM ingested spans allotment = max(actual_apm_hosts, committed_apm_hosts) × 150 GB/host/month

Profiled container allotment = max(actual_apm_enterprise_hosts, committed) × 4/host
```

### Phase 5: Compare & Classify

For each product, classify status:

| Status | Condition |
|--------|-----------|
| 🟢 OK | Usage ≤ committed (or allotment) |
| 🟡 Warning | Usage at 80–100% of committed |
| 🔴 Over | Usage > committed — on-demand charges apply |
| ⚪ Unused | No usage detected for committed product |

For month-to-date analysis, project to full month:
```
monthly_projection = (usage_so_far / days_elapsed) × days_in_month
```

### Phase 6: Generate Report

Output the report using the template from [report-template.md](report-template.md).

## Important Notes

- EUM metrics may differ from Plan & Usage by 10–20%. Always note this disclaimer.
- **Logs Index** has no `retention` tag on EUM metrics. Filter by `datadog_index` and manually map each index to its retention from the Indexes page.
- **Flex Logs** has no EUM metric — instruct user to check Plan & Usage manually.
- **RUM sessions** are count-type metrics — always use `.as_count().rollup(sum, monthly)` or `cumsum()`. Without `.as_count()`, values appear artificially small (~1-2).
- **Gauge EUM metrics** (hosts, containers) must NOT be summed over time — use `last` or `max` time aggregator only.
- Container allotment uses `max(actual_usage, commitment)` not just commitment.
- Allotments are NOT shared across container types (infra vs profiled vs security).

## Additional Resources

- For full metrics catalog and allotment tables, see [metrics-reference.md](metrics-reference.md)
- For report output template, see [report-template.md](report-template.md)
