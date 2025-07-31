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

# Deploy to Kubernetes or Docker Compose based on mode
if [ "$DEPLOYMENT_MODE" = "kubernetes" ]; then
  # Check if kubectl can connect to cluster
  if ! kubectl cluster-info >/dev/null 2>&1; then
    print_error "No Kubernetes cluster detected!"
    print_info "Please install k3s/k8s on the host system first, or use --docker-compose flag"
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
  
  # Create a temporary kustomization overlay with proper URL configuration
  print_info "Creating deployment configuration..."
  mkdir -p /tmp/invisible-deploy
  cp -r k8s /tmp/invisible-deploy/
  
  # Create override kustomization based on deployment type
  if [ "$NO_DOMAIN" = "true" ]; then
    print_info "Configuring for IP-based access..."
    # Create a patch for the URL config instead of a separate kustomization
    cat > /tmp/invisible-deploy/k8s/overlays/production/url-config-patch.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: url-config
data:
  API_PUBLIC_URL: "http://${SERVER_IP}:30084"
  SUPABASE_PUBLIC_URL: "http://${SERVER_IP}:30082"
  SITE_URL: "http://${SERVER_IP}:30080"
  API_EXTERNAL_URL: "http://${SERVER_IP}:30082"
EOF
    
    # Add the patch to production kustomization
    cd /tmp/invisible-deploy/k8s/overlays/production
    kustomize edit add patch --path url-config-patch.yaml --kind ConfigMap --name url-config
    cd /app
    
    print_success "Configured with IP-based URLs"
    echo "  API URL: http://${SERVER_IP}:30084"
    echo "  Supabase URL: http://${SERVER_IP}:30082"
  else
    print_info "Configuring for domain-based access..."
    # Create a patch for the URL config
    cat > /tmp/invisible-deploy/k8s/overlays/production/url-config-patch.yaml <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: url-config
data:
  API_PUBLIC_URL: "https://api.${DOMAIN}"
  SUPABASE_PUBLIC_URL: "https://api.${DOMAIN}"
  SITE_URL: "https://${DOMAIN}"
  API_EXTERNAL_URL: "https://api.${DOMAIN}"
EOF
    
    # Add the patch to production kustomization
    cd /tmp/invisible-deploy/k8s/overlays/production
    kustomize edit add patch --path url-config-patch.yaml --kind ConfigMap --name url-config
    cd /app
    
    print_success "Configured with domain URLs"
    echo "  API URL: https://api.${DOMAIN}"
    echo "  Supabase URL: https://api.${DOMAIN}"
  fi
  
  # Apply the configuration
  print_info "Applying Kubernetes configuration..."
  kubectl apply -k /tmp/invisible-deploy/k8s/overlays/production/
  
  # Create ArgoCD application for production
  print_info "Creating ArgoCD application for production..."
  kubectl apply -f argocd/apps/app-of-apps.yaml
  
  print_success "Production deployment completed!"
  print_info "ArgoCD is now managing the production deployment"
  print_info "The production overlay with NodePort services has been applied"
  
  echo ""
  echo "Monitor deployment progress with:"
  echo "  kubectl get pods -n invisible"
  echo ""
  echo "Once pods are running, services will be accessible at:"
  echo "  UI Hub: http://${SERVER_IP:-localhost}:30080"
  echo "  UI Chat: http://${SERVER_IP:-localhost}:30081"
  echo "  API: http://${SERVER_IP:-localhost}:30082"
  echo ""
  echo "To access ArgoCD UI:"
  echo "  kubectl port-forward svc/argocd-server -n argocd 8080:443"
  echo "  Then visit https://localhost:8080"
  echo "  Username: admin"
  echo "  Password: kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
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