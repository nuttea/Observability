# Usage Attribution Implementation Guide

## Phase 1: Tag Preparation (Week 1)

1. Run this skill's analysis to identify recommended tags
2. Fix tag gaps:
   - Increase coverage to >80% for chosen tags
   - Standardize tag values (lowercase, consistent separators)
   - Document tag meanings and allowed values
3. Verify tags exist across all products (infra, APM, logs)

## Phase 2: Configure in Datadog (Week 2)

**Admin access required.**

1. Go to: https://app.datadoghq.com/billing/usage-attribution
2. Click "Edit Tags"
3. Select 3 tags (e.g., `team`, `env`, `service`)
4. Save configuration
5. Wait 24-48 hours for first data

## Phase 3: Validation (Week 3)

After 48 hours, check:
- **High "no tag" percentage** -- tags not widely adopted
- **Unexpected distributions** -- tag values may be wrong
- **Missing services/teams** -- some resources not tagged

Target: <15% unattributed usage.

## Phase 4: Optimization (Week 4+)

### Create Cost Dashboards

Recommended widgets:
1. Usage by Team (bar chart)
2. Usage by Environment (pie chart)
3. Usage by Service (treemap)
4. Trend over Time (timeseries)
5. Unattributed Usage (single value -- target <15%)

### Set Up Monitors

1. **Unattributed Usage Alert**: Alert when "no tag" usage >20%
2. **Cost Anomaly Alert**: Alert when team/service costs spike >30%
3. **Tag Coverage Degradation**: Alert when tag coverage drops <75%

### Ongoing

- Track cost per team (target: fair distribution)
- Monthly cost reviews by team
- Optimize highest-cost services

## If Coverage is Low (<60%)

### Option: Start Simple

**Phase 1**: Just use `env` -- easiest to implement, immediate prod vs non-prod value

**Phase 2** (6 months): Add `team` after improving coverage to >80%

**Phase 3** (12 months): Add 3rd tag (`service`, `application`, or `cost_center`)

### Option: Use Infrastructure Tags

Use `region`, `availability_zone`, `instance_type` -- usually 100% coverage (auto-assigned by cloud). Less business-aligned but provides immediate value.

## Success Metrics

**Month 1**: Attribution enabled, <20% unattributed, cost dashboards created

**Month 3**: <15% unattributed, teams understand their costs, first optimizations

**Month 6**: <10% unattributed, regular cost reviews, measurable reductions
