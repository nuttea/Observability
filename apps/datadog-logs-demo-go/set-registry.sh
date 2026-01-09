#!/bin/bash

# Script to configure Docker registry for Datadog logs demo application
# Usage:
#   export DOCKER_USER=myregistry.io/myuser
#   ./set-registry.sh
#
# Or:
#   DOCKER_USER=myregistry.io/myuser ./set-registry.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if DOCKER_USER is set
if [ -z "$DOCKER_USER" ]; then
    echo -e "${RED}Error: DOCKER_USER environment variable is not set${NC}"
    echo ""
    echo "Usage:"
    echo "  export DOCKER_USER=myregistry.io/myuser"
    echo "  ./set-registry.sh"
    echo ""
    echo "Examples:"
    echo "  export DOCKER_USER=docker.io/johndoe"
    echo "  export DOCKER_USER=123456789.dkr.ecr.us-east-1.amazonaws.com"
    echo "  export DOCKER_USER=gcr.io/my-project"
    exit 1
fi

echo -e "${GREEN}Using Docker registry: ${DOCKER_USER}${NC}"
echo ""

# Files to update
FILES=(
    "k8s/deployment-test-a.yaml"
    "k8s/deployment-test-b.yaml"
    "k8s/deployment.yaml"
)

# Backup original files
echo -e "${YELLOW}Creating backups...${NC}"
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        cp "$file" "${file}.bak"
        echo "  ✓ Backed up: ${file} → ${file}.bak"
    fi
done
echo ""

# Update image references in deployment files
echo -e "${YELLOW}Updating deployment files...${NC}"
for file in "${FILES[@]}"; do
    if [ -f "$file" ]; then
        # Replace image: datadog-logs-demo:latest with full registry path
        sed -i.tmp "s|image: datadog-logs-demo:latest|image: ${DOCKER_USER}/datadog-logs-demo:latest|g" "$file"
        rm -f "${file}.tmp"
        echo "  ✓ Updated: $file"
    else
        echo "  ⚠ Skipped: $file (not found)"
    fi
done
echo ""

# Show what was changed
echo -e "${GREEN}Changes applied:${NC}"
echo "  Old: image: datadog-logs-demo:latest"
echo "  New: image: ${DOCKER_USER}/datadog-logs-demo:latest"
echo ""

# Next steps
echo -e "${GREEN}Next steps:${NC}"
echo ""
echo "1. Build and tag your Docker image:"
echo "   ${YELLOW}docker build -t datadog-logs-demo:latest .${NC}"
echo "   ${YELLOW}docker tag datadog-logs-demo:latest ${DOCKER_USER}/datadog-logs-demo:latest${NC}"
echo ""
echo "2. Push to your registry:"
echo "   ${YELLOW}docker push ${DOCKER_USER}/datadog-logs-demo:latest${NC}"
echo ""
echo "3. Deploy to Kubernetes:"
echo "   ${YELLOW}make k8s-deploy-all${NC}"
echo ""
echo -e "${GREEN}Tip:${NC} To restore original files, run:"
echo "   ${YELLOW}./restore-registry.sh${NC}"
echo ""
