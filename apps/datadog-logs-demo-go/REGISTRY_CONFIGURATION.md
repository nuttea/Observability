# Docker Registry Configuration Guide

This guide explains how to configure the application to use your Docker registry using the provided automation scripts.

## Overview

The application includes two helper scripts:
- **`set-registry.sh`** - Configures deployment files to use your Docker registry
- **`restore-registry.sh`** - Restores original deployment files

## Quick Start

### Basic Usage

```bash
# Set your Docker registry
export DOCKER_USER=docker.io/yourusername

# Run the configuration script
./set-registry.sh

# Build, tag, and push
docker build -t datadog-logs-demo:latest .
docker push ${DOCKER_USER}/datadog-logs-demo:latest

# Deploy
make k8s-deploy-all
```

## Supported Registries

### Docker Hub

```bash
export DOCKER_USER=docker.io/yourusername
./set-registry.sh
```

**Push:**
```bash
docker login
docker push docker.io/yourusername/datadog-logs-demo:latest
```

### Amazon ECR (Elastic Container Registry)

```bash
export DOCKER_USER=123456789.dkr.ecr.us-east-1.amazonaws.com
./set-registry.sh
```

**Push:**
```bash
# Login to ECR
aws ecr get-login-password --region us-east-1 | \
  docker login --username AWS --password-stdin 123456789.dkr.ecr.us-east-1.amazonaws.com

# Push image
docker push 123456789.dkr.ecr.us-east-1.amazonaws.com/datadog-logs-demo:latest
```

**Create ECR repository first:**
```bash
aws ecr create-repository --repository-name datadog-logs-demo --region us-east-1
```

### Google Container Registry (GCR)

```bash
export DOCKER_USER=gcr.io/my-project-id
./set-registry.sh
```

**Push:**
```bash
# Configure Docker to use gcloud credentials
gcloud auth configure-docker

# Push image
docker push gcr.io/my-project-id/datadog-logs-demo:latest
```

### Azure Container Registry (ACR)

```bash
export DOCKER_USER=myregistry.azurecr.io
./set-registry.sh
```

**Push:**
```bash
# Login to ACR
az acr login --name myregistry

# Push image
docker push myregistry.azurecr.io/datadog-logs-demo:latest
```

### GitHub Container Registry (GHCR)

```bash
export DOCKER_USER=ghcr.io/yourusername
./set-registry.sh
```

**Push:**
```bash
# Login to GHCR
echo $GITHUB_TOKEN | docker login ghcr.io -u yourusername --password-stdin

# Push image
docker push ghcr.io/yourusername/datadog-logs-demo:latest
```

## What the Script Does

### set-registry.sh

1. **Validates** that `DOCKER_USER` environment variable is set
2. **Creates backups** of all deployment files:
   - `k8s/deployment-test-a.yaml.bak`
   - `k8s/deployment-test-b.yaml.bak`
   - `k8s/deployment.yaml.bak`
3. **Updates** all deployment files:
   - Changes `image: datadog-logs-demo:latest`
   - To `image: ${DOCKER_USER}/datadog-logs-demo:latest`
4. **Displays** next steps for building and pushing

### restore-registry.sh

1. **Restores** original deployment files from backups
2. **Removes** backup files after restoration
3. **Reports** success or missing backups

## Examples

### Example 1: Docker Hub

```bash
# Set registry
export DOCKER_USER=docker.io/john.doe

# Configure
./set-registry.sh

# Build and tag
make docker-build
docker tag datadog-logs-demo:latest docker.io/john.doe/datadog-logs-demo:latest

# Login and push
docker login
docker push docker.io/john.doe/datadog-logs-demo:latest

# Deploy
make k8s-deploy-all
```

### Example 2: AWS ECR

```bash
# Variables
export AWS_ACCOUNT_ID=123456789012
export AWS_REGION=us-east-1
export DOCKER_USER=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Create ECR repository
aws ecr create-repository \
  --repository-name datadog-logs-demo \
  --region ${AWS_REGION}

# Configure
./set-registry.sh

# Build
make docker-build

# Tag
docker tag datadog-logs-demo:latest \
  ${DOCKER_USER}/datadog-logs-demo:latest

# Login to ECR
aws ecr get-login-password --region ${AWS_REGION} | \
  docker login --username AWS --password-stdin ${DOCKER_USER}

# Push
docker push ${DOCKER_USER}/datadog-logs-demo:latest

# Deploy
make k8s-deploy-all
```

### Example 3: Local Kubernetes (No Registry)

For local development with kind, minikube, or Docker Desktop:

```bash
# Build locally
make docker-build

# Load into local cluster
kind load docker-image datadog-logs-demo:latest
# Or: minikube image load datadog-logs-demo:latest

# Deploy (no need to run set-registry.sh)
make k8s-deploy-all
```

## File Changes

The script modifies these lines in deployment files:

**Before:**
```yaml
spec:
  containers:
  - name: datadog-logs-demo
    image: datadog-logs-demo:latest
```

**After (example with Docker Hub):**
```yaml
spec:
  containers:
  - name: datadog-logs-demo
    image: docker.io/johndoe/datadog-logs-demo:latest
```

## Kubernetes Image Pull Secrets

If using a **private registry**, create an image pull secret:

### Docker Hub

```bash
kubectl create secret docker-registry regcred \
  --docker-server=docker.io \
  --docker-username=yourusername \
  --docker-password=yourpassword \
  --docker-email=your.email@example.com \
  -n datadog-test-a

# Repeat for datadog-test-b
kubectl create secret docker-registry regcred \
  --docker-server=docker.io \
  --docker-username=yourusername \
  --docker-password=yourpassword \
  --docker-email=your.email@example.com \
  -n datadog-test-b
```

### AWS ECR

```bash
# Create secret for ECR
kubectl create secret docker-registry regcred \
  --docker-server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ${AWS_REGION}) \
  -n datadog-test-a

# Repeat for datadog-test-b
kubectl create secret docker-registry regcred \
  --docker-server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$(aws ecr get-login-password --region ${AWS_REGION}) \
  -n datadog-test-b
```

### Add to Deployment

Edit deployment files and add:

```yaml
spec:
  template:
    spec:
      imagePullSecrets:
      - name: regcred
      containers:
      - name: datadog-logs-demo
        image: your-registry/datadog-logs-demo:latest
```

## Verification

### Check Registry Configuration

```bash
# View current image in deployment
grep "image:" k8s/deployment-test-a.yaml
grep "image:" k8s/deployment-test-b.yaml

# Expected output (after running set-registry.sh):
# image: docker.io/yourusername/datadog-logs-demo:latest
```

### Check Backups

```bash
# List backup files
ls -la k8s/*.bak

# View backup content
cat k8s/deployment-test-a.yaml.bak | grep "image:"
```

### Verify Image Pull

```bash
# Check pod events
kubectl describe pod -n datadog-test-a -l app=datadog-logs-demo

# Look for:
# Successfully pulled image "your-registry/datadog-logs-demo:latest"
```

## Troubleshooting

### Issue: DOCKER_USER not set

**Error:**
```
Error: DOCKER_USER environment variable is not set
```

**Solution:**
```bash
export DOCKER_USER=your-registry/your-username
./set-registry.sh
```

### Issue: Image pull errors

**Error:**
```
Failed to pull image "registry/image:latest": authentication required
```

**Solution:**
Create image pull secret (see Kubernetes Image Pull Secrets section above)

### Issue: Want to use local images again

**Solution:**
```bash
# Restore original files
./restore-registry.sh

# Verify restoration
grep "image:" k8s/deployment-test-a.yaml
# Should show: image: datadog-logs-demo:latest
```

### Issue: Backup files lost

If backup files are missing, you can manually edit deployment files or restore from git:

```bash
# Restore from git
git checkout k8s/deployment-test-a.yaml k8s/deployment-test-b.yaml k8s/deployment.yaml
```

## Advanced: Using Different Registries per Namespace

If you need different registries for different namespaces:

```bash
# Configure test-a with Docker Hub
export DOCKER_USER=docker.io/johndoe
sed -i '' "s|image: datadog-logs-demo:latest|image: ${DOCKER_USER}/datadog-logs-demo:latest|g" k8s/deployment-test-a.yaml

# Configure test-b with ECR
export DOCKER_USER=123456789.dkr.ecr.us-east-1.amazonaws.com
sed -i '' "s|image: datadog-logs-demo:latest|image: ${DOCKER_USER}/datadog-logs-demo:latest|g" k8s/deployment-test-b.yaml
```

## Best Practices

1. **Use consistent registry** across all namespaces for simplicity
2. **Always run set-registry.sh** before first deployment to remote clusters
3. **Keep backups** until deployment is verified
4. **Use image pull secrets** for private registries
5. **Test locally first** before pushing to remote registry
6. **Document your registry** in team documentation

## Reference

- [QUICKSTART.md](QUICKSTART.md) - Quick deployment guide
- [DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md) - Detailed multi-namespace deployment
- [README.md](README.md) - Main documentation
