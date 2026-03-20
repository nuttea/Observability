# SLI/SLO Analysis Report Template

Use this template structure for the final report output.

````markdown
# SLI/SLO ANALYSIS REPORT

**Date**: YYYY-MM-DD
**Services Analyzed**: N
**Existing SLOs**: M
**Coverage**: M/N (X%)

---

## Executive Summary

Analyzed N services for SLI definition and SLO readiness.

Current State:
- X services have SLOs (Y% coverage)
- Z services need SLOs
- W services have performance issues

Recommended Actions:
- Create X new SLOs
- Investigate Y high-error services
- Monitor Z services approaching SLO violations

---

## Service-by-Service Analysis

### [Service Name]

**Current Performance (7 days)**:
- Total Requests: X
- Request Rate: X req/s
- Error Rate: X% → Availability: X%
- Latency: P50: Xms, P75: Xms, P95: Xms, P99: Xms

**Recommended SLIs**:

#### 1. Availability SLI
- Metric: `(successful_requests / total_requests) * 100`
- Current: X%
- Recommended SLO Target: X% (30-day window)
- Error Budget: X% (allows ~N errors/month)

#### 2. Latency SLI (P95)
- Metric: 95th percentile latency
- Current: Xms
- Recommended SLO Target: <Xms

**High-Risk Endpoints**:
1. [endpoint] - Error Rate: X%, P95: Xms

**Existing SLO** (if any):
- Name, current value, target, budget remaining, status

[Repeat for each service]

---

## SLO Coverage Gap Analysis

Services WITHOUT SLOs: Z

Priority for SLO Creation:
1. [Service] - [Reason: high traffic / critical / high errors]
2. [Service] - [Reason]

---

## Recommended SLO Definitions

### Service: [name]

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

---

## Error Budget Health

| Service | SLO          | Current | Target | Budget | Status |
| ------- | ------------ | ------- | ------ | ------ | ------ |
| [name]  | Availability | 99.95%  | 99.9%  | 75%    | ✅     |
| [name]  | Latency      | 345ms   | 500ms  | 90%    | ✅     |

---

## Next Review

Recommended: 30 days
Focus areas: [Based on findings]
````
