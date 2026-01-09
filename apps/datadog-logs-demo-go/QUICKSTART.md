# Quick Start Guide

## Prerequisites

- Go 1.21 or higher
- Docker
- Kubernetes cluster (EKS)
- kubectl configured
- Datadog Agent deployed (see `../../agent/eks-logs-only/`)

## Option 1: Run Locally

```bash
# Download dependencies
make deps

# Run the application
make run
```

The application will start generating logs to stdout in JSON format.

## Option 2: Run with Docker

```bash
# Build Docker image
make docker-build

# Run container
make docker-run
```

## Option 3: Deploy to Kubernetes

### Step 1: Configure Docker Registry (Optional - for remote registries)

If using a **remote Docker registry** (Docker Hub, ECR, GCR, etc.), use the provided script:

```bash
# Set your Docker registry
export DOCKER_USER=docker.io/yourusername
# Or for ECR: export DOCKER_USER=123456789.dkr.ecr.us-east-1.amazonaws.com
# Or for GCR: export DOCKER_USER=gcr.io/my-project

# Run the configuration script
./set-registry.sh
```

The script will automatically update all deployment files with your registry.

**Skip this step** if using local Kubernetes (kind, minikube, Docker Desktop) - the default `datadog-logs-demo:latest` will work.

### Step 2: Build and Push Image

```bash
# Build the Docker image
make docker-build

# If using REMOTE registry (after running set-registry.sh):
docker push ${DOCKER_USER}/datadog-logs-demo:latest

# If using LOCAL Kubernetes:
# For kind: kind load docker-image datadog-logs-demo:latest
# For minikube: minikube image load datadog-logs-demo:latest
```

### Step 3: Deploy

```bash
# Create namespaces and deploy
make k8s-deploy

# Check status
make k8s-status

# View logs
make k8s-logs
```

## Verify Logs in Datadog

1. Navigate to **Logs → Explorer** in Datadog
2. Filter by: `service:logs-demo` or `kube_namespace:datadog-test-a`
3. You should see logs with various `event_type` values

## Quick Examples

### View Business KPI Logs

```
service:logs-demo event_type:business_kpi
```

### View Error Logs

```
service:logs-demo level:error
```

### Calculate Average Transaction Value

```
service:logs-demo event_type:transaction |
measure @transaction_value |
avg(@transaction_value)
```

### Monitor API Latency (P95)

```
service:logs-demo event_type:api_request |
measure @duration_ms |
p95(@duration_ms)
```

## Cleanup

```bash
# Delete deployment
make k8s-delete

# Delete namespaces (optional)
kubectl delete namespace datadog-test-a datadog-test-b

# Restore original deployment files (if you ran set-registry.sh)
./restore-registry.sh
```

## Troubleshooting

### Logs not appearing in Datadog

1. Check pod status:
   ```bash
   kubectl get pods -n datadog-test-a
   ```

2. Check pod logs:
   ```bash
   kubectl logs -n datadog-test-a -l app=datadog-logs-demo
   ```

3. Verify Datadog Agent is collecting from the namespace:
   ```bash
   kubectl exec -n datadog -it <datadog-agent-pod> -- agent status
   ```

4. Check Datadog Agent configuration:
   - Ensure `containerIncludeLogs` includes `kube_namespace:datadog-test-a`
   - See `../../agent/eks-logs-only/datadog-values.yaml`

### Image pull errors

If using a private registry, create an image pull secret:

```bash
kubectl create secret docker-registry regcred \
  --docker-server=<your-registry> \
  --docker-username=<username> \
  --docker-password=<password> \
  -n datadog-test-a
```

Then add to deployment:

```yaml
spec:
  imagePullSecrets:
  - name: regcred
```

## Next Steps

- See [README.md](README.md) for detailed feature documentation
- Learn about creating custom metrics from logs
- Set up monitors and alerts
- Build dashboards with log data
