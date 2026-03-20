---
name: datadog-sli-slo-analysis
description: Analyze services to define SLIs and recommend SLOs using real APM performance data from Datadog MCP tools. Get request rates, error rates, and latency percentiles (p50, p75, p95, p99) for services and endpoints. Use when the user wants to define SLIs, create SLOs, analyze service performance, identify reliability targets, check SLO compliance, or mentions "error budget", "availability target", or "latency SLI".
---

# Datadog SLI/SLO Analysis

Define Service Level Indicators (SLIs) and recommend Service Level Objectives (SLOs) based on real APM performance data.

## Workflow

### 1. Discover Services

Call `get_all_services` with `query: "*"`, `from: <7 days ago>`, `to: <now>`.

### 2. Analyze Each Service

For each service, call `get_service_stats_realtime` to extract SLI candidates:

- **Availability SLI**: `(total_requests - total_errors) / total_requests * 100`
- **Error Rate SLI**: `error_percentage`
- **Latency SLI**: `p95_latency_ms` or `p99_latency_ms`
- **Throughput SLI**: `requests_per_second`

### 3. Discover API Endpoints

For services needing endpoint-level SLIs, call `get_service_endpoints`.

Identify critical endpoints:
- High traffic (top 10 by requests)
- High error rate (>1%)
- High latency (p95 >500ms)

### 4. Check Existing SLO Coverage

Call `list_slos` to get current SLOs. Compare services with SLOs vs services discovered. Identify gaps.

### 5. Recommend SLOs

For each service WITHOUT an SLO, recommend targets using the SLI framework below. Set targets **below** current performance to provide error budget buffer.

### 6. Generate Report

See [references/report-template.md](references/report-template.md) for the full output template. Include:
- Executive summary (services analyzed, existing SLOs, coverage percentage)
- Per-service analysis with current metrics and recommended SLIs/SLOs
- SLO coverage gap analysis prioritized by traffic and error rate
- Ready-to-use SLO definitions in YAML format
- Error budget health table for existing SLOs

## SLI Definition Framework

### For Web Services

1. **Availability SLI** (required): Request success rate. Target: 99.5-99.99% depending on criticality.
2. **Latency SLI** (required): P95 or P99 latency. Target: <500ms (P95) or <1000ms (P99).
3. **Throughput SLI** (optional): Requests per second. Target: baseline + buffer.

### For Batch Jobs

1. **Success Rate SLI**
2. **Duration SLI**
3. **Freshness SLI**

### For APIs

1. **Endpoint Availability** (per critical endpoint)
2. **Endpoint Latency** (P95)
3. **Overall Service Availability**

## SLO Definition Format

Provide ready-to-use Datadog SLO definitions:

```yaml
type: metric
name: '[Service] Availability'
thresholds:
  - target: 99.5
    timeframe: 30d
    warning: 99.7
query:
  numerator: 'sum:trace.[service].request.hits{!error:true}.as_count()'
  denominator: 'sum:trace.[service].request.hits{*}.as_count()'
```

## Key Principles

- **Start conservative**: Set achievable targets based on current performance
- **Iterate**: Tighten targets as reliability improves
- **Alert on budget**: Warn when <20% error budget remaining
- **Focus coverage**: Prioritize SLOs for critical, high-traffic services over low-traffic ones
