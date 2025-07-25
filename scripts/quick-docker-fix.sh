#!/bin/bash
set -e

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --docker-username <username>   Docker Hub username"
    echo "  --docker-password <password>   Docker Hub password/token"
    echo "  --help                         Show this help message"
    echo ""
    echo "Example:"
    echo "  $0 --docker-username myuser --docker-password mytoken"
    echo ""
    echo "Note: Docker credentials can also be set via environment variables:"
    echo "  DOCKER_USERNAME and DOCKER_PASSWORD"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --docker-username)
            DOCKER_USERNAME="$2"
            shift 2
            ;;
        --docker-password)
            DOCKER_PASSWORD="$2"
            shift 2
            ;;
        --help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

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

# Get Docker Hub credentials from environment or prompt
if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
    read -p "Docker Hub username: " DOCKER_USERNAME
    read -s -p "Docker Hub password/token: " DOCKER_PASSWORD
    echo ""
fi

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