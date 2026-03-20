# Tag Recommendation Framework

## Scoring Criteria

Score each candidate tag:

```
tag_score = coverage * 0.3 + cardinality_score * 0.2 + business_value * 0.3 + actionability * 0.2
```

### Criteria Details

| Criterion       | Weight | Ideal                                    |
| --------------- | ------ | ---------------------------------------- |
| Coverage        | 30%    | >80% of resources tagged                 |
| Cardinality     | 20%    | <50 unique values, stable over time      |
| Business Value  | 30%    | Maps to cost centers, teams, or products |
| Actionability   | 20%    | Insights lead to concrete optimizations  |

## Common Scenario Recommendations

### Scenario A: Team Chargeback

**Tags**: `team`, `env`, `service`

- **team**: Who to charge (primary dimension)
- **env**: Split by environment (prod costs more)
- **service**: Microservice-level detail

### Scenario B: Project-Based Billing

**Tags**: `application`, `env`, `team`

- **application**: Which business project
- **env**: Environment costs
- **team**: Secondary ownership

### Scenario C: Service-Level Cost Analysis

**Tags**: `service`, `env`, `team`

Best for SaaS/microservices architectures with granular service cost visibility.

## Decision Matrix

| Goal                      | Recommended Tags                      | Rationale                                          |
| ------------------------- | ------------------------------------- | -------------------------------------------------- |
| **Team Chargeback**       | `team`, `env`, `service`              | Allocate costs to engineering teams                |
| **Business Unit Billing** | `business_unit`, `cost_center`, `env` | Corporate cost allocation with formal accounting   |
| **Product Economics**     | `product`, `env`, `tier`              | Track costs per business product line              |
| **Multi-Tenant SaaS**     | `customer`, `env`, `tier`             | Bill customers for their usage                     |
| **Service Cost Analysis** | `service`, `env`, `team`              | Optimize service-level economics                   |

## Business Model Considerations

**SaaS/Multi-tenant**: Primary `customer_id` or `tenant`, secondary `env`, `tier`

**Internal IT**: Primary `team` or `department`, secondary `env`, `cost_center`

**Project-Based**: Primary `project` or `application`, secondary `env`, `team`

## Organizational Structure

**Centralized Platform Team**: Use `team`, `service`, `env` -- chargeback to engineering teams

**Distributed Teams**: Use `business_unit`, `cost_center`, `env` -- chargeback to business units

## Cost Allocation Goals

**Simple Showback** (awareness): `team`, `env` -- show teams their consumption

**Strict Chargeback** (billing): `cost_center`, `env`, `tier` -- bill internal customers

**Service Cost Tracking**: `service`, `env`, `tier` -- per-service economics

## Tag Cardinality Impact

- **Low** (1-20 values): Ideal -- easy reports, clear chargeback
- **Medium** (20-100 values): Acceptable -- may need grouping
- **High** (>100 values): Avoid -- unusable for attribution, performance issues
