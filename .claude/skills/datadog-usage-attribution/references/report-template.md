# Usage Attribution Report Template

Use this template structure for the final report output.

```markdown
# DATADOG USAGE ATTRIBUTION STRATEGY

**Date**: YYYY-MM-DD
**Analysis Period**: Past 30 days
**Current Attribution Status**: Not Configured / Configured with [tags]

---

## Executive Summary

Based on analysis of X hosts, Y services, and Z monitors:

**Recommended Attribution Tags**: `tag1`, `tag2`, `tag3`

**Expected Benefit**:
- X% cost attribution (Y% unattributed)
- [Primary benefit, e.g., clear team chargeback]
- [Secondary benefit]

**Prerequisites**:
- [Tag gap to fix]
- [Standardization needed]

---

## Tag Analysis

### Tag Candidate Scores

| Tag         | Coverage | Cardinality | Business Value | Actionability | Score  |
| ----------- | -------- | ----------- | -------------- | ------------- | ------ |
| [tag]       | X%       | N values    | HIGH/MED/LOW   | HIGH/MED/LOW  | XX/100 |

### Recommended Tag #1: [tag] (PRIMARY)
- Coverage: X% → Target: Y%
- Cardinality: N values
- Business Value: [explanation]
- Action: [what to do]

### Recommended Tag #2: [tag] (SECONDARY)
[Same structure]

### Recommended Tag #3: [tag] (TERTIARY)
[Same structure]

---

## Estimated Usage Distribution

### By [Tag 1]:

| Value     | Hosts | Services | Est. Log % | Est. Cost % |
| --------- | ----- | -------- | ---------- | ----------- |
| [value]   | N     | N        | X%         | X%          |
| (no tag)  | N     | N        | X%         | X% ⚠️       |

### By [Tag 2]:
[Same structure]

### By [Tag 3]:
[Same structure]

---

## Readiness Assessment

### Chosen Tags: [tag1], [tag2], [tag3]

| Tag    | Coverage | Cardinality | Standardized | Ready |
| ------ | -------- | ----------- | ------------ | ----- |
| [tag1] | X%       | N           | ✅/⚠️         | ✅/⚠️  |

**Readiness Score**: XX/100
**Estimated Unattributed Costs**: X%

---

## Implementation Roadmap

### Week 1: Tag Preparation
- [ ] [Action items]

### Week 2: Enable Attribution
- [ ] Configure in Datadog UI
- [ ] Wait 24-48 hours

### Week 3: Validation
- [ ] Check data quality
- [ ] Verify <15% unattributed

### Week 4+: Optimization
- [ ] Create dashboards
- [ ] Set up monitors

---

## Cost Optimization Opportunities

| Opportunity             | Est. Savings | Action             |
| ----------------------- | ------------ | ------------------ |
| [opportunity]           | $X/month     | [action]           |

**Total Potential Savings**: $X/month
```
