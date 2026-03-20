# Tagging Compliance Report Template

Use this template structure for the final report output.

```markdown
# DATADOG TAGGING COMPLIANCE REPORT

**Date**: YYYY-MM-DD
**Resources Analyzed**: Hosts (N), Services (M), Monitors (X), Logs (sample), Dashboards (Y)
**Overall Compliance Score**: XX/100

---

## Executive Summary

Tagging compliance: [Excellent/Good/Needs Improvement/Poor]

Key Findings:
- ✅ [Positive finding]
- ⚠️ [Issue requiring attention]
- ❌ [Critical issue]

---

## Compliance by Category

| Resource Type  | Score  | Key Issues           |
| -------------- | ------ | -------------------- |
| Infrastructure | XX/40  | ...                  |
| APM Services   | XX/30  | ...                  |
| Monitors       | XX/20  | ...                  |
| Logs & Dash.   | XX/10  | ...                  |

---

## Priority Action Items

### 🔴 HIGH Priority (Implement in 1 week)
1. [Action] - Impact: [description]

### 🟡 MEDIUM Priority (Implement in 1 month)
1. [Action] - Impact: [description]

### 🟢 LOW Priority (Nice to have)
1. [Action] - Impact: [description]

---

## Detailed Findings

### Infrastructure Tagging: XX/40

Total Hosts: N

**Reserved Tags Coverage**:
- env: X% (Y/N hosts)
- host: 100% (auto-assigned)

**Critical Tags Coverage**:
- team: X% (Y/N hosts) - Target: >85%, Gap: Z hosts

**Hosts Missing Critical Tags**:
1. hostname-1: Missing env, team
2. hostname-2: Missing team

**Tag Value Violations**:
- host-abc: env=development (should be dev/stage/prod)

### APM Service Tagging: XX/30

Services Discovered: N

**UST Compliance**:
- Complete (service + env + version): X/N (Y%)
- Partial (service + env): X/N (Y%)

**Per-Service Tag Coverage**:
[Table or list per service with tag presence]

### Monitor Tagging: XX/20

Total Monitors: N
- team tag: X% (Y/N)
- priority tag: X% (Y/N)

**Monitors Missing Critical Tags**:
[List monitors without team/priority]

### Log Tagging

Sample Size: N logs
- service: X%
- source: X%
- host: X%

### Dashboard & SLO Tagging

Dashboards: N total, X without tags
SLOs: N total, X without tags

---

## Tag Standardization Issues

**CamelCase Violations**: [list with corrections]
**Inconsistent Values**: [list with standardizations]
**High Cardinality Tags**: [list with recommendations]

---

## Implementation Recommendations

[Summarize top actions with specific instructions]
```
