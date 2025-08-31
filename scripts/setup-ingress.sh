#!/bin/bash

# setup-ingress.sh - Configure ingress for domain access on K3s
# This script sets up Traefik ingress routes for the Invisible platform

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

print_header() {
    echo -e "${BLUE}"
    echo "=================================================="
    echo "$1"
    echo "=================================================="
    echo -e "${NC}"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."
    
    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl not found. Please ensure K3s is installed."
        exit 1
    fi
    
    # Check if we can connect to cluster
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi
    
    # Check if invisible namespace exists
    if ! kubectl get namespace invisible &> /dev/null; then
        print_error "Invisible namespace not found. Please deploy the platform first."
        exit 1
    fi
    
    # Check if Traefik is running (K3s default)
    if ! kubectl get pods -n kube-system | grep -q traefik; then
        print_warning "Traefik not found in kube-system. K3s might be using a different setup."
    else
        print_success "Traefik ingress controller detected"
    fi
}

# Main setup
main() {
    print_header "Invisible Platform - Ingress Setup"
    
    check_prerequisites
    
    echo ""
    print_info "This script will set up domain-based ingress routes for the Invisible platform."
    print_info "Services will be accessible via subdomains:"
    echo "  • hub.yourdomain.com"
    echo "  • chat.yourdomain.com"
    echo "  • api.yourdomain.com"
    echo "  • supabase.yourdomain.com"
    echo ""
    
    setup_domain_routing
}

# Setup domain-based routing
setup_domain_routing() {
    print_header "Setting up Domain-based Routing"
    
    read -p "Enter your base domain (e.g., invisible.yourdomain.com): " BASE_DOMAIN
    
    if [[ -z "$BASE_DOMAIN" ]]; then
        print_error "Domain is required"
        exit 1
    fi
    
    print_info "Creating ingress routes for:"
    echo "  • hub.$BASE_DOMAIN     → UI Hub"
    echo "  • chat.$BASE_DOMAIN    → UI Chat"
    echo "  • api.$BASE_DOMAIN     → API"
    echo "  • supabase.$BASE_DOMAIN → Supabase Kong"
    echo ""
    
    read -p "Enable HTTPS with Let's Encrypt? (y/n): " ENABLE_HTTPS
    
    # Create the ingress manifest in a temp file
    INGRESS_FILE="/tmp/invisible-ingress.yaml"
    
    cat > "$INGRESS_FILE" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: invisible-ingress
  namespace: invisible
  annotations:
    kubernetes.io/ingress.class: traefik
EOF
    
    if [[ "$ENABLE_HTTPS" == "y" ]]; then
        read -p "Enter email for Let's Encrypt: " LE_EMAIL
        cat >> /tmp/invisible-ingress.yaml <<EOF
    cert-manager.io/cluster-issuer: letsencrypt-prod
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
EOF
    else
        cat >> /tmp/invisible-ingress.yaml <<EOF
    traefik.ingress.kubernetes.io/router.entrypoints: web
EOF
    fi
    
    cat >> /tmp/invisible-ingress.yaml <<EOF
spec:
  rules:
  - host: hub.$BASE_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: invisible-ui-hub
            port:
              number: 80
  - host: chat.$BASE_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: invisible-ui-chat
            port:
              number: 80
  - host: api.$BASE_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: invisible-api
            port:
              number: 4300
  - host: supabase.$BASE_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: supabase-kong
            port:
              number: 8000
EOF
    
    if [[ "$ENABLE_HTTPS" == "y" ]]; then
        cat >> /tmp/invisible-ingress.yaml <<EOF
  tls:
  - hosts:
    - hub.$BASE_DOMAIN
    - chat.$BASE_DOMAIN
    - api.$BASE_DOMAIN
    - supabase.$BASE_DOMAIN
    secretName: invisible-tls-cert
EOF
        
        # Setup cert-manager if needed
        setup_cert_manager "$LE_EMAIL"
    fi
    
    # Apply the ingress
    print_info "Applying ingress configuration..."
    kubectl apply -f "$INGRESS_FILE"
    
    print_success "Domain-based routing configured!"
    
    # Get server IP
    SERVER_IP=$(curl -s ifconfig.me 2>/dev/null || echo "YOUR-SERVER-IP")
    
    print_header "Next Steps"
    print_warning "Configure your DNS A records:"
    echo "  hub.$BASE_DOMAIN     → $SERVER_IP"
    echo "  chat.$BASE_DOMAIN    → $SERVER_IP"
    echo "  api.$BASE_DOMAIN     → $SERVER_IP"
    echo "  supabase.$BASE_DOMAIN → $SERVER_IP"
    echo ""
    
    if [[ "$ENABLE_HTTPS" == "y" ]]; then
        print_info "HTTPS will be automatically configured once DNS is set up."
    else
        print_info "Access your services via:"
        echo "  http://hub.$BASE_DOMAIN"
        echo "  http://chat.$BASE_DOMAIN"
        echo "  http://api.$BASE_DOMAIN"
        echo "  http://supabase.$BASE_DOMAIN"
    fi
}


# Setup cert-manager for HTTPS
setup_cert_manager() {
    local email=$1
    
    print_info "Setting up cert-manager for Let's Encrypt..."
    
    # Check if cert-manager is installed
    if ! kubectl get namespace cert-manager &> /dev/null; then
        print_info "Installing cert-manager..."
        kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.13.0/cert-manager.yaml
        
        print_info "Waiting for cert-manager to be ready..."
        kubectl wait --namespace cert-manager --for=condition=ready pod --selector=app.kubernetes.io/instance=cert-manager --timeout=300s
    else
        print_info "cert-manager already installed"
    fi
    
    # Create ClusterIssuer for Let's Encrypt
    cat > /tmp/letsencrypt-issuer.yaml <<EOF
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: $email
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: traefik
EOF
    
    kubectl apply -f /tmp/letsencrypt-issuer.yaml
    print_success "Let's Encrypt issuer configured"
}

# Show status
show_status() {
    print_header "Ingress Status"
    
    print_info "Ingress resources:"
    kubectl get ingress -n invisible
    
    if kubectl get namespace cert-manager &> /dev/null; then
        print_info "Certificates:"
        kubectl get certificates -n invisible
    fi
    
    print_info "Services:"
    kubectl get svc -n invisible
}

# Parse arguments
case "${1:-}" in
    status)
        show_status
        ;;
    *)
        main
        echo ""
        print_info "Run '$0 status' to check ingress status"
        ;;
esac