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

# Cleanup Kubernetes resources
cleanup_k8s() {
  print_info "Starting Kubernetes cleanup..."
  
  # Check if kubectl is available
  if ! command -v kubectl >/dev/null 2>&1; then
    print_warning "kubectl not found. Skipping Kubernetes cleanup."
    return 0
  fi
  
  # Check if cluster is accessible
  if ! kubectl cluster-info >/dev/null 2>&1; then
    print_warning "No Kubernetes cluster detected. Skipping cleanup."
    return 0
  fi
  
  # Delete namespaces
  for ns in invisible argocd; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
      print_info "Deleting namespace: $ns"
      kubectl delete namespace "$ns" --force --grace-period=0 --wait=false 2>/dev/null || true
    fi
  done
  
  # Wait a bit for namespace deletion to start
  sleep 5
  
  # Force remove finalizers if namespaces are stuck
  for ns in invisible argocd; do
    if kubectl get namespace "$ns" >/dev/null 2>&1; then
      print_info "Force removing finalizers from namespace: $ns"
      kubectl get namespace "$ns" -o json | \
        jq '.spec.finalizers = []' | \
        kubectl replace --raw /api/v1/namespaces/"$ns"/finalize -f - 2>/dev/null || true
    fi
  done
  
  # Clean up cluster-wide resources
  print_info "Cleaning up cluster-wide resources..."
  
  # Delete any Invisible-related ClusterRoles and ClusterRoleBindings
  kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/part-of=invisible --force --grace-period=0 2>/dev/null || true
  kubectl delete clusterrole,clusterrolebinding -l app.kubernetes.io/part-of=argocd --force --grace-period=0 2>/dev/null || true
  
  # Delete any orphaned PVs
  print_info "Cleaning up persistent volumes..."
  for pv in $(kubectl get pv -o name | grep -E "(invisible|argocd)" || true); do
    kubectl delete "$pv" --force --grace-period=0 2>/dev/null || true
  done
  
  # Clean up any stuck pods
  print_info "Cleaning up any stuck pods..."
  for pod in $(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.metadata.namespace | test("invisible|argocd")) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || true); do
    ns=$(echo "$pod" | cut -d'/' -f1)
    name=$(echo "$pod" | cut -d'/' -f2)
    kubectl delete pod "$name" -n "$ns" --force --grace-period=0 2>/dev/null || true
  done
  
  print_success "Kubernetes cleanup completed!"
}

# Main execution
cleanup_k8s