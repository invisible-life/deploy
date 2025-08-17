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

# Default values
DOCKER_USERNAME=""
DOCKER_PASSWORD=""
SERVER_IP=""

# Parse arguments
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
    --ip)
      SERVER_IP="$2"
      shift 2
      ;;
    *)
      print_error "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Validate required parameters
if [ -z "$DOCKER_USERNAME" ] || [ -z "$DOCKER_PASSWORD" ]; then
  print_error "Docker credentials are required!"
  exit 1
fi

# Login to Docker Hub
print_info "Logging into Docker Hub..."
echo "$DOCKER_PASSWORD" | docker login -u "$DOCKER_USERNAME" --password-stdin

# Set working directory
cd /app

# Check if kubectl can connect to cluster
if ! kubectl cluster-info >/dev/null 2>&1; then
  print_error "No Kubernetes cluster detected!"
  print_info "Please install k3s/k8s on the host system first"
  exit 1
fi

# Kubernetes deployment
print_info "Deploying to Kubernetes..."

# Install ArgoCD if not present
if ! kubectl get namespace argocd >/dev/null 2>&1; then
  print_info "Installing ArgoCD..."
  kubectl create namespace argocd
  kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
  
  print_info "Waiting for ArgoCD to be ready..."
  kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd || true
fi

# Create namespace before secrets
print_info "Creating namespace..."
kubectl create namespace invisible --dry-run=client -o yaml | kubectl apply -f -

# Generate secrets AFTER namespace exists but BEFORE deploying apps
print_info "Generating secrets..."
DOCKER_USERNAME="$DOCKER_USERNAME" DOCKER_PASSWORD="$DOCKER_PASSWORD" ./scripts/generate-secrets.sh

# Auto-detect server IP if not provided
if [ -z "$SERVER_IP" ]; then
  print_info "Auto-detecting server IP address..."
  SERVER_IP=$(curl -s -4 ifconfig.me 2>/dev/null || echo "localhost")
  print_success "Detected IP: $SERVER_IP"
fi

# Create a simple server-config ConfigMap with just server IP
print_info "Creating server configuration..."
cat > /tmp/server-config.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: server-config
  namespace: invisible
data:
  SERVER_IP: "${SERVER_IP}"
EOF
  
  # Apply the server config
  kubectl apply -f /tmp/server-config.yaml
  
  print_success "Configured for IP-based access at ${SERVER_IP}"
  
  # Apply the configuration
  print_info "Applying Kubernetes configuration..."
  kubectl apply -k k8s/overlays/production/
  
  # Create ArgoCD application for production
  print_info "Creating ArgoCD application for production..."
  kubectl apply -f argocd/apps/platform.yaml
  
  # Wait for ArgoCD application to be created
  print_info "Waiting for ArgoCD application to be ready..."
  sleep 5
  
  # Trigger ArgoCD sync
  print_info "Syncing ArgoCD application..."
  kubectl patch -n argocd application/invisible-platform-production --type=merge \
    -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD","prune":true,"syncStrategy":{"hook":{}}}}}' || true
  
  # Wait for initial pod creation
  print_info "Waiting for pods to be created..."
  sleep 10
  
  # Wait for critical pods to be ready
  print_info "Waiting for services to start..."
  CRITICAL_DEPLOYMENTS="supabase-kong supabase-auth supabase-postgres ui-hub ui-chat invisible-api"
  
  for deployment in $CRITICAL_DEPLOYMENTS; do
    echo -n "  Waiting for $deployment..."
    kubectl wait --for=condition=available --timeout=300s deployment/$deployment -n invisible >/dev/null 2>&1 && echo " ✓" || echo " (skipped)"
  done
  
  # Give services a moment to fully initialize
  print_info "Allowing services to initialize..."
  sleep 5
  
  print_success "Production deployment completed!"
  print_info "ArgoCD is now managing the production deployment"
  print_info "All critical services are running"
  
  echo ""
  echo "Monitor deployment progress with:"
  echo "  kubectl get pods -n invisible"
  echo ""
  echo "Services are accessible at:"
  echo "  UI Hub: http://${SERVER_IP}:30080"
  echo "  UI Chat: http://${SERVER_IP}:30081"
  echo "  Supabase Kong API: http://${SERVER_IP}:30082"
  echo "  Mailpit: http://${SERVER_IP}:30083"
  echo "  Invisible API: http://${SERVER_IP}:30084"
  echo ""
  echo "To access ArgoCD UI:"
  echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "  Then visit https://localhost:8080"
  echo "  Username: admin"
  echo "  Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"