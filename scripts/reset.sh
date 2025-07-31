#!/bin/bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Print functions
print_info() {
  echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
  echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
  echo -e "${RED}❌ $1${NC}"
}

print_warning() {
  echo -e "${YELLOW}⚠️  $1${NC}"
}

print_header() {
  echo -e "\n${YELLOW}======================================${NC}"
  echo -e "${YELLOW}  $1${NC}"
  echo -e "${YELLOW}======================================${NC}\n"
}

# Reset function for use inside the deploy container
reset_deployment() {
  print_header "RESETTING INVISIBLE DEPLOYMENT"
  
  # Check if kubectl is available
  if command -v kubectl >/dev/null 2>&1 && kubectl cluster-info >/dev/null 2>&1; then
    print_info "Cleaning up Kubernetes resources..."
    
    # Delete invisible namespace
    if kubectl get namespace invisible >/dev/null 2>&1; then
      print_info "Deleting invisible namespace..."
      kubectl delete namespace invisible --force --grace-period=0 2>/dev/null || true
    fi
    
    # Delete ArgoCD namespace
    if kubectl get namespace argocd >/dev/null 2>&1; then
      print_info "Deleting ArgoCD namespace..."
      kubectl delete namespace argocd --force --grace-period=0 2>/dev/null || true
    fi
    
    # Clean up any orphaned PVCs
    print_info "Cleaning up persistent volume claims..."
    kubectl delete pvc --all-namespaces --all --force --grace-period=0 2>/dev/null || true
    
    # Clean up any orphaned PVs
    print_info "Cleaning up persistent volumes..."
    kubectl delete pv --all --force --grace-period=0 2>/dev/null || true
    
    print_success "Kubernetes resources cleaned up"
  else
    print_warning "No Kubernetes cluster detected or kubectl not available"
  fi
  
  # Clean up Docker resources if Docker Compose was used
  if [ -f /opt/invisible/deploy/docker-compose.yml ]; then
    print_info "Cleaning up Docker Compose deployment..."
    cd /opt/invisible/deploy 2>/dev/null || true
    docker-compose down -v --remove-orphans 2>/dev/null || true
  fi
  
  # Clean up deployment files
  if [ -d /opt/invisible ]; then
    print_info "Removing deployment files..."
    rm -rf /opt/invisible/*
  fi
  
  # Clean up any temporary files
  print_info "Cleaning up temporary files..."
  rm -rf /tmp/invisible-deploy /tmp/url-patch.yaml /tmp/kustomization-*.yaml 2>/dev/null || true
  
  print_success "Deployment reset completed!"
}

# Main execution
if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  echo "Usage: $0"
  echo "Resets the Invisible platform deployment"
  exit 0
fi

reset_deployment