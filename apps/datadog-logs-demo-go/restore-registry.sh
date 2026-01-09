#!/bin/bash

# Script to restore original deployment files
# Usage: ./restore-registry.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Files to restore
FILES=(
    "k8s/deployment-test-a.yaml"
    "k8s/deployment-test-b.yaml"
    "k8s/deployment.yaml"
)

echo -e "${YELLOW}Restoring original deployment files...${NC}"
echo ""

RESTORED=0
NOT_FOUND=0

for file in "${FILES[@]}"; do
    if [ -f "${file}.bak" ]; then
        mv "${file}.bak" "$file"
        echo -e "  ${GREEN}✓${NC} Restored: $file"
        ((RESTORED++))
    else
        echo -e "  ${YELLOW}⚠${NC} No backup found: ${file}.bak"
        ((NOT_FOUND++))
    fi
done

echo ""

if [ $RESTORED -gt 0 ]; then
    echo -e "${GREEN}Successfully restored ${RESTORED} file(s)${NC}"
    echo ""
    echo "Deployment files now use the default image:"
    echo "  image: datadog-logs-demo:latest"
fi

if [ $NOT_FOUND -gt 0 ]; then
    echo -e "${YELLOW}Warning: ${NOT_FOUND} backup file(s) not found${NC}"
fi

echo ""
