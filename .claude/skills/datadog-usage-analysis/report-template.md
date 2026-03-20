# Usage Analysis Report Template

Use this template when generating the comparison report. Replace placeholders with actual data.

---

## Output Format

```markdown
# Datadog Usage Analysis Report

**Org:** [org name or ID]
**Period:** [start date] — [end date] ([X] days elapsed, [Y] days in month)
**Generated:** [today's date]

> Estimated usage metrics may differ from billable usage by 10–20%. Plan & Usage page is the authoritative source.

---

## Committed vs. Actual Usage

### Infrastructure & APM

| Product | SKU Tier | Committed | Actual (avg) | Actual (max) | Monthly Projection | Status |
|---------|----------|-----------|-------------|-------------|-------------------|--------|
| Infra Hosts | [tier] | [N] | [avg] | [max] | [proj] | [status] |
| APM Hosts | [tier] | [N] | [avg] | [max] | [proj] | [status] |

### Containers & Allotments

| Product | Allotment Basis | Allotment | Actual (avg) | Overage/hr | Est. Monthly Cost | Status |
|---------|----------------|-----------|-------------|-----------|------------------|--------|
| Infra Containers | [N] hosts × [rate] | [allotment] | [avg] | [overage] | $[cost] | [status] |
| Profiled Containers | [N] hosts × 4 | [allotment] | [avg] | [overage] | — | [status] |

### Custom Metrics

| Product | Allotment Basis | Allotment | Actual | Status |
|---------|----------------|-----------|--------|--------|
| Indexed Custom Metrics | [N] hosts × [rate] | [allotment] | [actual] | [status] |

### Logs

| Product | Committed | Actual (MTD) | Monthly Projection | Status |
|---------|-----------|-------------|-------------------|--------|
| Logs Ingest | [N] GB/mo | [X] GB | [proj] GB | [status] |
| Logs Index ([retention]) | [N]M events/mo | [X]M events | [proj]M events | [status] |
| Flex Logs Stored | [N]M events | ⚠️ Check Plan & Usage | — | — |

> Note: Logs Index usage is broken down by `datadog_index`. No `retention` tag exists on EUM metrics — index-to-retention mapping from Indexes page.
> Note: Flex Logs has no EUM metric. User must check Plan & Usage → Logs manually.

### RUM Sessions

| SKU | Committed | Actual (MTD) | Monthly Projection | Status |
|-----|-----------|-------------|-------------------|--------|
| RUM Measure | [N]K sessions | [X] sessions | [proj] | [status] |
| RUM Investigate | [N]K sessions | [X] sessions | [proj] | [status] |
| Session Replay | [N]K sessions | [X] sessions | [proj] | [status] |

> RUM metrics are count-type. Queried with `.as_count().rollup(sum, monthly)`.

### APM Spans & Allotments

| Product | Allotment Basis | Allotment | Actual (MTD) | Monthly Projection | Status |
|---------|----------------|-----------|-------------|-------------------|--------|
| Indexed Spans | [N] hosts × 1M | [allotment]M | [X]M | [proj]M | [status] |
| Ingested Spans | [N] hosts × 150GB | [allotment] GB | [X] GB | [proj] GB | [status] |

### Other Products (if committed)

| Product | Committed | Actual | Status |
|---------|-----------|--------|--------|
| [product] | [amount] | [actual] | [status] |

---

## Summary Dashboard

| Product | Committed | Actual (Period) | Monthly Projection | Status |
|---------|-----------|----------------|-------------------|--------|
| [row per product] | | | | |

---

## Top Action Items

1. **[Highest risk product]** — [specific recommendation with numbers]
2. **[Second highest risk]** — [specific recommendation]
3. **[Third]** — [specific recommendation]

---

## Queries Used

| Product | Datadog Query |
|---------|--------------|
| [product] | `[exact query used]` |

---

## Manual Checks Required

- [ ] Flex Logs Stored → [Plan & Usage → Logs](https://app.datadoghq.com/billing/usage?category=logs)
- [ ] Logs Index retention mapping → [Logs → Indexes](https://app.datadoghq.com/logs/pipelines/indexes)
- [ ] Plan & Usage for authoritative billing numbers → [Plan & Usage](https://app.datadoghq.com/billing/usage)
```

## Status Legend

| Icon | Meaning | Condition |
|------|---------|-----------|
| 🟢 | OK | Usage ≤ committed or allotment |
| 🟡 | Warning | Usage at 80–100% of limit |
| 🔴 | Over | Usage exceeds limit — on-demand charges |
| ⚪ | Unused | No usage for a committed product |

## Projection Formula

```
monthly_projection = (actual_mtd / days_elapsed) × total_days_in_month
```

For gauge metrics (hosts, containers): use average or max of the period.
For count metrics (sessions, events, bytes): sum MTD then project.
