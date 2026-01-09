# Tags Reference - Multi-Namespace Deployment

Quick reference for tags applied at different levels in the multi-namespace deployment.

## Tag Comparison Table

| Tag | datadog-test-a | datadog-test-b | Applied At |
|-----|----------------|----------------|------------|
| **Environment & Identity** |
| `env` | `development` | `staging` | Namespace + Deployment |
| `service` | `logs-demo-dev` | `logs-demo-staging` | Deployment |
| `version` | `1.0.0` | `1.0.0` | Deployment |
| **Team & Organization** |
| `team` | `platform-engineering` | `application-team` | Namespace |
| `cost-center` | `engineering` | `product` | Namespace |
| **Infrastructure** |
| `system` | `observability-demo` | `ecommerce-platform` | Namespace |
| `cluster` | `eks-dev` | `eks-staging` | Namespace |
| `region` | `us-east-1` | `us-west-2` | Namespace |
| **Business Context** |
| `business-unit` | `infrastructure` | `sales` | Namespace |
| `project` | `datadog-logs-testing` | `checkout-service` | Namespace |
| **Compliance & Security** |
| `compliance` | `sox` | `pci-dss` | Namespace |
| `data-classification` | `internal` | `confidential` | Namespace |
| **Application Metadata** |
| `application` | `logs-demo` | `logs-demo` | Pod Annotation |
| `component` | `demo-generator` | `demo-generator` | Pod Annotation |
| `deployed-by` | `platform-team` | `app-team` | Pod Annotation |
| `source` | `golang` | `golang` | Pod Annotation |

## Tag Sources Breakdown

### Level 1: Namespace Labels (Inherited by ALL pods)

**Applied via:** `k8s/namespace.yaml`

```yaml
labels:
  tags.datadoghq.com/env: "..."
  tags.datadoghq.com/team: "..."
  tags.datadoghq.com/cost-center: "..."
  tags.datadoghq.com/system: "..."
  tags.datadoghq.com/cluster: "..."
  tags.datadoghq.com/region: "..."
  tags.datadoghq.com/business-unit: "..."
  tags.datadoghq.com/project: "..."
  tags.datadoghq.com/compliance: "..."
  tags.datadoghq.com/data-classification: "..."
```

**Purpose:** Organization-wide context, cost allocation, compliance tracking

### Level 2: Deployment Labels (Inherited by pods in this deployment)

**Applied via:** `k8s/deployment-test-*.yaml`

```yaml
labels:
  tags.datadoghq.com/service: "..."
  tags.datadoghq.com/env: "..."
  tags.datadoghq.com/version: "..."
```

**Purpose:** Service identification, unified service tagging

### Level 3: Pod Annotations (Most specific)

**Applied via:** Autodiscovery annotations in deployment

```yaml
annotations:
  ad.datadoghq.com/datadog-logs-demo.logs: |
    [{
      "source": "golang",
      "service": "...",
      "tags": [
        "application:logs-demo",
        "component:demo-generator",
        "deployed-by:..."
      ]
    }]
```

**Purpose:** Application-specific metadata, deployment details

## Common Query Patterns

### Filter by Environment

```
# Development logs only
env:development

# Staging logs only
env:staging

# Both environments
env:(development OR staging)
```

### Filter by Team

```
# Platform team logs
team:platform-engineering

# Application team logs
team:application-team
```

### Filter by Cost Center

```
# Engineering cost center
cost-center:engineering

# Product cost center
cost-center:product
```

### Filter by Compliance

```
# SOX compliance data
compliance:sox

# PCI-DSS compliance data
compliance:pci-dss
```

### Filter by Region

```
# US East logs
region:us-east-1

# US West logs
region:us-west-2
```

### Combined Filters

```
# Platform team development logs
team:platform-engineering env:development

# High-value transactions in staging
env:staging event_type:transaction transaction_value:>500

# SOX compliance errors
compliance:sox level:error

# PCI-DSS payment processing
compliance:pci-dss event_type:payment_processing
```

## Analytics Queries

### Cost Center Log Volume

```
service:(logs-demo-dev OR logs-demo-staging) |
count by cost-center
```

### Team Performance Comparison

```
service:(logs-demo-dev OR logs-demo-staging) event_type:api_request |
measure @duration_ms by team |
avg(@duration_ms)
```

### Regional Error Rates

```
service:(logs-demo-dev OR logs-demo-staging) level:error |
count by region, cluster
```

### Compliance Audit

```
# All SOX-related activities
compliance:sox |
count by event_type, service

# All PCI-DSS payment activities
compliance:pci-dss event_type:payment_processing |
count by fraud_status
```

### Business Unit Analytics

```
# Log volume by business unit
service:(logs-demo-dev OR logs-demo-staging) |
count by business-unit, project
```

## Dashboard Widget Examples

### 1. Log Volume by Environment

**Widget Type:** Timeseries
**Query:** `service:(logs-demo-dev OR logs-demo-staging) | count by env`
**Visualization:** Area chart with env as the series

### 2. Cost Center Distribution

**Widget Type:** Pie Chart
**Query:** `service:(logs-demo-dev OR logs-demo-staging) | count by cost-center`
**Shows:** Proportional log volume per cost center

### 3. Team Error Rates

**Widget Type:** Top List
**Query:** `service:(logs-demo-dev OR logs-demo-staging) level:error | count by team`
**Shows:** Error counts by team

### 4. Regional Performance Heatmap

**Widget Type:** Heatmap
**Query:** `service:(logs-demo-dev OR logs-demo-staging) event_type:api_request | measure @duration_ms by region`
**Shows:** Latency distribution across regions

### 5. Compliance Coverage

**Widget Type:** Query Value
**Query:** `service:(logs-demo-dev OR logs-demo-staging) | count by compliance`
**Shows:** Number of logs per compliance framework

## Monitor Examples

### High Error Rate by Team

```yaml
Alert Type: Log Monitor
Query: service:(logs-demo-dev OR logs-demo-staging) level:error
Group by: team, env
Alert threshold: > 50 errors in 5 minutes
Message: "High error rate detected for team {{team.name}} in {{env.name}}"
```

### Cost Center Log Anomaly

```yaml
Alert Type: Anomaly Monitor
Query: service:(logs-demo-dev OR logs-demo-staging) | count by cost-center
Alert: Anomalous log volume increase
Message: "Unusual log volume for cost center {{cost-center.name}}"
```

### Compliance Data Classification Alert

```yaml
Alert Type: Log Monitor
Query: compliance:pci-dss data-classification:confidential level:error
Alert threshold: > 10 errors in 10 minutes
Message: "Errors in PCI-DSS confidential data processing"
```

## Tag Best Practices

1. **Consistency** - Use the same tag keys across all namespaces
2. **Hierarchy** - More specific tags override general ones
3. **Naming** - Use lowercase with hyphens (kebab-case)
4. **Cardinality** - Avoid high-cardinality tags (user IDs, transaction IDs)
5. **Purpose** - Each tag should serve a clear filtering or grouping purpose

## Adding Custom Tags

### At Namespace Level

```bash
kubectl label namespace datadog-test-a tags.datadoghq.com/owner=john.doe
```

### At Deployment Level

Edit `k8s/deployment-test-*.yaml`:

```yaml
labels:
  tags.datadoghq.com/custom-tag: "custom-value"
```

### At Pod Level

Edit Autodiscovery annotations in deployment:

```yaml
annotations:
  ad.datadoghq.com/datadog-logs-demo.logs: |
    [{
      "tags": ["existing-tag:value", "new-tag:value"]
    }]
```

## Verification Commands

```bash
# Check namespace labels
kubectl get namespace datadog-test-a -o jsonpath='{.metadata.labels}' | jq

# Check pod labels
kubectl get pod <pod-name> -n datadog-test-a -o jsonpath='{.metadata.labels}' | jq

# Check pod annotations
kubectl get pod <pod-name> -n datadog-test-a -o jsonpath='{.metadata.annotations}' | jq
```

## Reference Documents

- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Full deployment instructions
- [README.md](README.md) - Feature documentation
- [QUICKSTART.md](QUICKSTART.md) - Quick start guide
- [k8s/namespace.yaml](k8s/namespace.yaml) - Namespace definitions
- [k8s/deployment-test-a.yaml](k8s/deployment-test-a.yaml) - Test-a deployment
- [k8s/deployment-test-b.yaml](k8s/deployment-test-b.yaml) - Test-b deployment
