# Deployment Guide - Multi-Namespace Setup

This guide walks you through deploying the Datadog Logs Demo application to both `datadog-test-a` and `datadog-test-b` namespaces with different tags for demonstration purposes.

## Overview

The application will be deployed to two namespaces with distinct tagging strategies to demonstrate:
- **Namespace-level tagging** - Tags inherited by all pods in the namespace
- **Deployment-level tagging** - Tags specific to the deployment
- **Pod-level tagging** - Tags via Autodiscovery annotations
- **Tag hierarchy** - How tags override and combine

## Namespace Tag Strategy

### datadog-test-a (Development Environment)

| Tag Category | Tag | Value | Purpose |
|--------------|-----|-------|---------|
| Environment | `env` | `development` | Development environment |
| Team | `team` | `platform-engineering` | Platform team ownership |
| Cost Center | `cost-center` | `engineering` | Cost allocation |
| System | `system` | `observability-demo` | System identifier |
| Cluster | `cluster` | `eks-dev` | Kubernetes cluster |
| Region | `region` | `us-east-1` | AWS region |
| Business Unit | `business-unit` | `infrastructure` | Business context |
| Project | `project` | `datadog-logs-testing` | Project name |
| Compliance | `compliance` | `sox` | Compliance requirements |
| Classification | `data-classification` | `internal` | Data sensitivity |

### datadog-test-b (Staging Environment)

| Tag Category | Tag | Value | Purpose |
|--------------|-----|-------|---------|
| Environment | `env` | `staging` | Staging environment |
| Team | `team` | `application-team` | Application team ownership |
| Cost Center | `cost-center` | `product` | Cost allocation |
| System | `system` | `ecommerce-platform` | System identifier |
| Cluster | `cluster` | `eks-staging` | Kubernetes cluster |
| Region | `region` | `us-west-2` | AWS region |
| Business Unit | `business-unit` | `sales` | Business context |
| Project | `project` | `checkout-service` | Project name |
| Compliance | `compliance` | `pci-dss` | Compliance requirements |
| Classification | `data-classification` | `confidential` | Data sensitivity |

## Prerequisites

1. **Kubernetes Cluster** - EKS cluster configured
2. **kubectl** - Configured to access your cluster
3. **Docker Image** - Built and available
4. **Datadog Agent** - Deployed with logs collection enabled (see `../../agent/eks-logs-only/`)
5. **Datadog Agent Configuration** - Must include both namespaces:
   ```yaml
   containerIncludeLogs: "kube_namespace:datadog-test-a kube_namespace:datadog-test-b"
   ```

## Step-by-Step Deployment

### Step 1: Build the Docker Image

```bash
# Navigate to the app directory
cd apps/datadog-logs-demo-go

# Build the Docker image
docker build -t datadog-logs-demo:latest .

# Tag for your registry (if using remote registry)
docker tag datadog-logs-demo:latest <your-registry>/datadog-logs-demo:latest

# Push to registry (if using remote registry)
docker push <your-registry>/datadog-logs-demo:latest
```

**Note**: If using a remote registry, update the `image` field in both deployment files:
- `k8s/deployment-test-a.yaml`
- `k8s/deployment-test-b.yaml`

### Step 2: Create Namespaces with Tags

```bash
# Create both namespaces with their respective tags
kubectl apply -f k8s/namespace.yaml

# Verify namespaces were created
kubectl get namespaces datadog-test-a datadog-test-b

# View namespace labels (tags)
kubectl get namespace datadog-test-a -o yaml | grep -A 20 labels
kubectl get namespace datadog-test-b -o yaml | grep -A 20 labels
```

Expected output:
```yaml
# datadog-test-a labels
labels:
  tags.datadoghq.com/env: "development"
  tags.datadoghq.com/team: "platform-engineering"
  tags.datadoghq.com/cost-center: "engineering"
  tags.datadoghq.com/system: "observability-demo"
  # ... more labels
```

### Step 3: Deploy to datadog-test-a Namespace

```bash
# Deploy to datadog-test-a
kubectl apply -f k8s/deployment-test-a.yaml

# Check deployment status
kubectl get deployments -n datadog-test-a

# Check pods
kubectl get pods -n datadog-test-a

# View pod details and labels
kubectl get pods -n datadog-test-a -o wide --show-labels
```

### Step 4: Deploy to datadog-test-b Namespace

```bash
# Deploy to datadog-test-b
kubectl apply -f k8s/deployment-test-b.yaml

# Check deployment status
kubectl get deployments -n datadog-test-b

# Check pods
kubectl get pods -n datadog-test-b

# View pod details and labels
kubectl get pods -n datadog-test-b -o wide --show-labels
```

### Step 5: Verify Deployments

```bash
# Check all pods across both namespaces
kubectl get pods -n datadog-test-a -l app=datadog-logs-demo
kubectl get pods -n datadog-test-b -l app=datadog-logs-demo

# View logs from datadog-test-a
kubectl logs -n datadog-test-a -l app=datadog-logs-demo --tail=20

# View logs from datadog-test-b
kubectl logs -n datadog-test-b -l app=datadog-logs-demo --tail=20
```

### Step 6: Verify Logs in Datadog

1. Navigate to **Logs → Explorer** in Datadog

2. **View logs from datadog-test-a:**
   ```
   kube_namespace:datadog-test-a
   ```

   Expected tags on logs:
   - `env:development`
   - `service:logs-demo-dev`
   - `team:platform-engineering`
   - `cost-center:engineering`
   - `system:observability-demo`
   - `cluster:eks-dev`
   - `region:us-east-1`
   - `business-unit:infrastructure`
   - `project:datadog-logs-testing`
   - `compliance:sox`
   - `data-classification:internal`
   - `application:logs-demo`
   - `component:demo-generator`

3. **View logs from datadog-test-b:**
   ```
   kube_namespace:datadog-test-b
   ```

   Expected tags on logs:
   - `env:staging`
   - `service:logs-demo-staging`
   - `team:application-team`
   - `cost-center:product`
   - `system:ecommerce-platform`
   - `cluster:eks-staging`
   - `region:us-west-2`
   - `business-unit:sales`
   - `project:checkout-service`
   - `compliance:pci-dss`
   - `data-classification:confidential`
   - `application:logs-demo`
   - `component:demo-generator`

4. **Compare tags between namespaces:**
   ```
   service:(logs-demo-dev OR logs-demo-staging) |
   count by service, team, cost-center, env
   ```

## Tag Hierarchy and Inheritance

Understanding how tags are applied and inherited:

```
┌─────────────────────────────────────────────────┐
│ Global Tags (from Datadog Agent Helm values)   │
│ - env:dev (from agent config)                  │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ Namespace Labels (tags.datadoghq.com/*)        │
│ - env:development / staging (OVERRIDES global) │
│ - team, cost-center, system, cluster, etc.     │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ Deployment Labels (tags.datadoghq.com/*)       │
│ - service:logs-demo-dev / logs-demo-staging    │
│ - version:1.0.0                                 │
└─────────────────────────────────────────────────┘
                      ↓
┌─────────────────────────────────────────────────┐
│ Pod Annotations (ad.datadoghq.com/<>.logs)      │
│ - application:logs-demo                         │
│ - component:demo-generator                      │
│ - deployed-by:platform-team / app-team         │
└─────────────────────────────────────────────────┘
```

**Key Points:**
- Later tags override earlier ones with the same key
- All tags are combined and sent with each log entry
- Namespace tags are inherited by all pods in that namespace
- Pod annotations provide the most specific tagging

## Useful Queries

### Compare Environments

```
# Revenue by environment
service:(logs-demo-dev OR logs-demo-staging) event_type:business_kpi |
sum:@revenue by env
```

```
# Error rate by team
service:(logs-demo-dev OR logs-demo-staging) level:error |
count by team, env
```

### Cost Center Analytics

```
# Log volume by cost center
service:(logs-demo-dev OR logs-demo-staging) |
count by cost-center
```

### Compliance Filtering

```
# PCI-DSS compliance logs only
compliance:pci-dss event_type:payment_processing
```

```
# SOX compliance logs only
compliance:sox
```

### Regional Analytics

```
# Logs by region
service:(logs-demo-dev OR logs-demo-staging) |
count by region, cluster
```

### Business Unit Tracking

```
# Logs by business unit
service:(logs-demo-dev OR logs-demo-staging) |
count by business-unit, project
```

## Scaling the Deployments

```bash
# Scale datadog-test-a deployment
kubectl scale deployment/datadog-logs-demo -n datadog-test-a --replicas=3

# Scale datadog-test-b deployment
kubectl scale deployment/datadog-logs-demo -n datadog-test-b --replicas=3

# Verify scaling
kubectl get deployments -n datadog-test-a
kubectl get deployments -n datadog-test-b
```

## Updating Tags

### Update Namespace Tags

```bash
# Add or update namespace labels
kubectl label namespace datadog-test-a tags.datadoghq.com/owner=john.doe --overwrite

# Remove a label
kubectl label namespace datadog-test-a tags.datadoghq.com/owner-
```

### Update Deployment Tags

```bash
# Edit deployment directly
kubectl edit deployment/datadog-logs-demo -n datadog-test-a

# Or update the YAML file and reapply
kubectl apply -f k8s/deployment-test-a.yaml
```

## Monitoring and Troubleshooting

### Check Pod Events

```bash
kubectl describe pod <pod-name> -n datadog-test-a
kubectl describe pod <pod-name> -n datadog-test-b
```

### View Datadog Agent Status

```bash
# Check if agent is collecting from both namespaces
kubectl exec -n datadog -it <datadog-agent-pod> -- agent status | grep -A 10 "Logs Agent"
```

### Verify Log Collection

```bash
# Watch logs in real-time
kubectl logs -n datadog-test-a -l app=datadog-logs-demo -f --tail=50
kubectl logs -n datadog-test-b -l app=datadog-logs-demo -f --tail=50
```

## Cleanup

### Delete Deployments Only

```bash
kubectl delete -f k8s/deployment-test-a.yaml
kubectl delete -f k8s/deployment-test-b.yaml
```

### Delete Everything (Including Namespaces)

```bash
kubectl delete namespace datadog-test-a
kubectl delete namespace datadog-test-b
```

**Note**: This will delete all resources in these namespaces.

## Makefile Commands

For convenience, you can use these Makefile commands:

```bash
# Deploy to both namespaces
make k8s-deploy-all

# View logs from test-a
make k8s-logs NS=datadog-test-a

# View logs from test-b
make k8s-logs NS=datadog-test-b

# Check status of both deployments
make k8s-status-all

# Delete both deployments
make k8s-delete-all
```

## Next Steps

1. **Create Dashboards** - Build dashboards comparing both environments
2. **Set Up Monitors** - Create monitors scoped to specific teams or cost centers
3. **Cost Analysis** - Track log volume by cost center
4. **Compliance Reporting** - Generate reports filtered by compliance tags
5. **Team Dashboards** - Create team-specific views using team tags

## Reference

- Namespace definitions: [k8s/namespace.yaml](k8s/namespace.yaml)
- Deployment for test-a: [k8s/deployment-test-a.yaml](k8s/deployment-test-a.yaml)
- Deployment for test-b: [k8s/deployment-test-b.yaml](k8s/deployment-test-b.yaml)
- Main README: [README.md](README.md)
- Quick Start: [QUICKSTART.md](QUICKSTART.md)
