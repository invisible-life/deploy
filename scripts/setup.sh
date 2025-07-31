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
DOMAIN=""
NO_DOMAIN="false"
SERVER_IP=""
DEPLOYMENT_MODE="kubernetes"  # Default to Kubernetes deployment

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
    --domain)
      DOMAIN="$2"
      shift 2
      ;;
    --no-domain)
      NO_DOMAIN="true"
      shift
      ;;
    --ip)
      SERVER_IP="$2"
      shift 2
      ;;
    --docker-compose)
      DEPLOYMENT_MODE="docker-compose"
      shift
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

# Create .env from example
print_info "Setting up environment configuration..."
cp .env.example .env

# Configure URLs based on deployment type
if [ "$NO_DOMAIN" = "true" ]; then
  # Use environment variables if set, otherwise use provided IP
  if [ -n "$API_PUBLIC_URL" ]; then
    sed -i "s|API_PUBLIC_URL=.*|API_PUBLIC_URL=$API_PUBLIC_URL|g" .env
  elif [ -n "$SERVER_IP" ]; then
    sed -i "s|API_PUBLIC_URL=.*|API_PUBLIC_URL=http://$SERVER_IP:4300|g" .env
  fi
  
  if [ -n "$SUPABASE_PUBLIC_URL" ]; then
    sed -i "s|SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=$SUPABASE_PUBLIC_URL|g" .env
  elif [ -n "$SERVER_IP" ]; then
    sed -i "s|SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=http://$SERVER_IP:8000|g" .env
  fi
  
  if [ -n "$API_EXTERNAL_URL" ]; then
    sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=$API_EXTERNAL_URL|g" .env
  elif [ -n "$SERVER_IP" ]; then
    sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=http://$SERVER_IP:8000|g" .env
  fi
  
  if [ -n "$SITE_URL" ]; then
    sed -i "s|SITE_URL=.*|SITE_URL=$SITE_URL|g" .env
  elif [ -n "$SERVER_IP" ]; then
    sed -i "s|SITE_URL=.*|SITE_URL=http://$SERVER_IP:3000|g" .env
  fi
  
  print_success "Configured for IP-based access${SERVER_IP:+ at $SERVER_IP}"
  
elif [ -n "$DOMAIN" ]; then
  # Configure for domain
  sed -i "s|API_PUBLIC_URL=.*|API_PUBLIC_URL=https://api.$DOMAIN|g" .env
  sed -i "s|SUPABASE_PUBLIC_URL=.*|SUPABASE_PUBLIC_URL=https://api.$DOMAIN|g" .env
  sed -i "s|API_EXTERNAL_URL=.*|API_EXTERNAL_URL=https://api.$DOMAIN|g" .env
  sed -i "s|SITE_URL=.*|SITE_URL=https://$DOMAIN|g" .env
  
  print_success "Configured for domain: $DOMAIN"
fi

# Generate secrets
print_info "Generating secrets..."
# Source the .env to get any existing values
source .env || true

# Install k3s if not present and we're deploying to Kubernetes
if [ "$DEPLOYMENT_MODE" = "kubernetes" ]; then
  if ! command -v kubectl >/dev/null 2>&1 || ! kubectl cluster-info >/dev/null 2>&1; then
    print_info "Installing k3s..."
    curl -sfL https://get.k3s.io | sh -
    
    # Wait for k3s to be ready
    print_info "Waiting for k3s to be ready..."
    sleep 10
    
    # Export kubeconfig
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    
    # Make kubectl accessible
    if [ -f /usr/local/bin/kubectl ]; then
      ln -sf /usr/local/bin/kubectl /usr/bin/kubectl 2>/dev/null || true
    fi
    
    # Wait for node to be ready
    print_info "Waiting for k3s node to be ready..."
    until kubectl get nodes | grep -q " Ready"; do
      echo -n "."
      sleep 5
    done
    echo ""
    print_success "k3s installed successfully!"
  fi
  
  # Kubernetes deployment
  print_info "Deploying to Kubernetes..."
  ./scripts/generate-secrets.sh
  
  # Install ArgoCD if not present
  if ! kubectl get namespace argocd >/dev/null 2>&1; then
    print_info "Installing ArgoCD..."
    kubectl create namespace argocd
    kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    
    print_info "Waiting for ArgoCD to be ready..."
    kubectl wait --for=condition=available --timeout=600s deployment/argocd-server -n argocd
  fi
  
  print_info "Deploying applications with ArgoCD..."
  kubectl create namespace invisible --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -f argocd/apps/app-of-apps.yaml
  
  print_success "ArgoCD applications deployed! Monitor progress with:"
  echo "  kubectl get applications -n argocd"
  echo "  kubectl get pods -n invisible"
else
  # Docker Compose deployment
  print_info "Using Docker Compose deployment..."
  
  # Generate local secrets for Docker Compose
  print_info "Generating local configuration..."
  
  # Copy deployment files to persistent volume
  print_info "Setting up deployment files..."
  mkdir -p /opt/invisible
  cp -r . /opt/invisible/deploy
  cd /opt/invisible/deploy
  
  # Run Supabase
  print_info "Starting Supabase services..."
  ./scripts/run-supabase-docker.sh
  
  print_success "Deployment complete!"
  echo ""
  echo "Services will be available at:"
  echo "  Supabase Studio: http://${SERVER_IP:-localhost}:3000"
  echo "  Supabase API: http://${SERVER_IP:-localhost}:8000"
  echo "  UI Hub: http://${SERVER_IP:-localhost}:4400"
  echo "  UI Chat: http://${SERVER_IP:-localhost}:4500"
  echo "  API: http://${SERVER_IP:-localhost}:4300"
fi