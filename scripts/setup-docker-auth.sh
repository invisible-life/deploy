#!/bin/bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Invisible Platform - Docker Hub Authentication Setup${NC}"
echo "===================================================="

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found. Please install kubectl first.${NC}"
    exit 1
fi

# Check if namespace exists
if ! kubectl get namespace invisible &> /dev/null; then
    echo -e "${YELLOW}Creating namespace 'invisible'...${NC}"
    kubectl create namespace invisible
fi

# Function to create Docker registry secret
create_docker_secret() {
    local username="$1"
    local password="$2"
    local email="${3:-noreply@invisible.life}"
    
    echo -e "${YELLOW}Creating Docker Hub secret...${NC}"
    
    kubectl create secret docker-registry dockerhub-secret \
        --namespace=invisible \
        --docker-server=docker.io \
        --docker-username="$username" \
        --docker-password="$password" \
        --docker-email="$email" \
        --dry-run=client -o yaml | kubectl apply -f -
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ Docker Hub secret created successfully!${NC}"
    else
        echo -e "${RED}❌ Failed to create Docker Hub secret${NC}"
        exit 1
    fi
}

# Check for existing secret
if kubectl get secret dockerhub-secret -n invisible &> /dev/null; then
    echo -e "${YELLOW}Docker Hub secret already exists. Do you want to update it? (y/n)${NC}"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Keeping existing secret."
        exit 0
    fi
fi

# Prompt for Docker Hub credentials
echo -e "${BLUE}Please enter your Docker Hub credentials:${NC}"
echo "(These are needed to pull the private invisiblelife images)"
echo ""

read -p "Docker Hub username: " DOCKER_USERNAME
read -s -p "Docker Hub password/token: " DOCKER_PASSWORD
echo ""
read -p "Email (optional, press Enter to skip): " DOCKER_EMAIL

# Create the secret
create_docker_secret "$DOCKER_USERNAME" "$DOCKER_PASSWORD" "$DOCKER_EMAIL"

echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. The deployments will automatically use this secret for pulling images"
echo "2. If deployments are already running, restart them:"
echo "   kubectl rollout restart deployment -n invisible --all"
echo ""
echo -e "${YELLOW}Note: It's recommended to use a Docker Hub access token instead of your password.${NC}"
echo "You can create one at: https://hub.docker.com/settings/security"