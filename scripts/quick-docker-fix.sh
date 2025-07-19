#!/bin/bash
set -e

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Quick Docker Hub Authentication Fix${NC}"
echo "===================================="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

echo -e "${YELLOW}This script will help you quickly fix the Docker image pull errors.${NC}"
echo ""

# Prompt for Docker Hub credentials
read -p "Docker Hub username: " DOCKER_USERNAME
read -s -p "Docker Hub password/token: " DOCKER_PASSWORD
echo ""

# Create the secret
echo -e "${BLUE}Creating Docker Hub secret...${NC}"
kubectl create secret docker-registry dockerhub-secret \
    --namespace=invisible \
    --docker-server=docker.io \
    --docker-username="$DOCKER_USERNAME" \
    --docker-password="$DOCKER_PASSWORD" \
    --docker-email="noreply@invisible.life" \
    --dry-run=client -o yaml | kubectl apply -f -

# Restart all deployments to pick up the new secret
echo -e "${BLUE}Restarting deployments...${NC}"
kubectl get deployments -n invisible -o name | xargs -I {} kubectl rollout restart {} -n invisible

echo ""
echo -e "${GREEN}✅ Done! The deployments should now be able to pull images.${NC}"
echo -e "${YELLOW}Monitor progress with: kubectl get pods -n invisible -w${NC}"