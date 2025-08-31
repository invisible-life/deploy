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
    echo "  • argocd.$BASE_DOMAIN  → ArgoCD"
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
            name: ui-hub
            port:
              number: 80
  - host: chat.$BASE_DOMAIN
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ui-chat
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
    
    # Create ArgoCD ingress (in argocd namespace)
    setup_argocd_ingress "$BASE_DOMAIN" "$ENABLE_HTTPS"
    
    # Update API configuration to use domain URLs
    update_api_config "$BASE_DOMAIN" "$ENABLE_HTTPS"
    
    print_success "Domain-based routing configured!"
    
    # Get server IPv4 address
    SERVER_IP=$(curl -4 -s ifconfig.me 2>/dev/null || \
                curl -s ipv4.icanhazip.com 2>/dev/null || \
                curl -s api.ipify.org 2>/dev/null || \
                kubectl get nodes -o wide | grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' | head -1 || \
                echo "YOUR-SERVER-IP")
    
    print_header "📋 REQUIRED DNS CONFIGURATION"
    
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}Add these DNS records in your domain provider's control panel:${NC}"
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════${NC}"
    echo ""
    # Detect if we got an IPv6 address (contains colons)
    if [[ "$SERVER_IP" == *":"* ]]; then
        RECORD_TYPE="AAAA"
        print_warning "IPv6 address detected. You'll need AAAA records instead of A records."
    else
        RECORD_TYPE="A"
    fi
    
    echo -e "${GREEN}Option 1: Individual ${RECORD_TYPE} Records (Recommended)${NC}"
    echo -e "  ${GREEN}Type${NC}    ${GREEN}Name/Host${NC}                     ${GREEN}Value/Points To${NC}"
    echo -e "  ────    ─────────                     ───────────────"
    echo -e "  ${BLUE}${RECORD_TYPE}${NC}       hub                      →    ${YELLOW}$SERVER_IP${NC}"
    echo -e "  ${BLUE}${RECORD_TYPE}${NC}       chat                     →    ${YELLOW}$SERVER_IP${NC}"
    echo -e "  ${BLUE}${RECORD_TYPE}${NC}       api                      →    ${YELLOW}$SERVER_IP${NC}"
    echo -e "  ${BLUE}${RECORD_TYPE}${NC}       supabase                 →    ${YELLOW}$SERVER_IP${NC}"
    echo -e "  ${BLUE}${RECORD_TYPE}${NC}       argocd                   →    ${YELLOW}$SERVER_IP${NC}"
    echo ""
    echo -e "${GREEN}Option 2: Wildcard ${RECORD_TYPE} Record (Easier but less flexible)${NC}"
    echo -e "  ${BLUE}${RECORD_TYPE}${NC}       *                        →    ${YELLOW}$SERVER_IP${NC}"
    echo -e "  ${CYAN}(This will route ALL subdomains to your server)${NC}"
    echo ""
    echo -e "${YELLOW}════════════════════════════════════════════════════════════════════${NC}"
    
    print_info "Common DNS Providers:"
    echo "  • Cloudflare: dash.cloudflare.com → Select Domain → DNS"
    echo "  • Namecheap: ap.www.namecheap.com → Domain List → Manage → Advanced DNS"
    echo "  • GoDaddy: dcc.godaddy.com → My Domains → DNS → Manage Zones"
    echo "  • Google Domains: domains.google.com → My domains → DNS"
    echo ""
    
    print_warning "DNS changes can take 5-30 minutes to propagate"
    
    if [[ "$ENABLE_HTTPS" == "y" ]]; then
        echo ""
        print_info "🔒 HTTPS Status:"
        echo "  • SSL certificates will be automatically generated after DNS is configured"
        echo "  • First visit might show a certificate warning while Let's Encrypt validates"
        echo ""
        print_success "Once DNS is configured, access your services at:"
        echo "  🌐 https://hub.$BASE_DOMAIN"
        echo "  💬 https://chat.$BASE_DOMAIN"
        echo "  🔌 https://api.$BASE_DOMAIN"
        echo "  🗄️  https://supabase.$BASE_DOMAIN"
        echo "  🚀 https://argocd.$BASE_DOMAIN"
    else
        echo ""
        print_success "Once DNS is configured, access your services at:"
        echo "  🌐 http://hub.$BASE_DOMAIN"
        echo "  💬 http://chat.$BASE_DOMAIN"
        echo "  🔌 http://api.$BASE_DOMAIN"
        echo "  🗄️  http://supabase.$BASE_DOMAIN"
        echo "  🚀 http://argocd.$BASE_DOMAIN"
    fi
    
    echo ""
    print_info "To verify DNS is working:"
    echo "  nslookup hub.$BASE_DOMAIN"
    echo "  # Should return: $SERVER_IP"
}


# Update domain configuration ConfigMap
update_api_config() {
    local base_domain=$1
    local enable_https=$2
    
    print_info "Updating domain configuration..."
    
    # Update only the BASE_DOMAIN and USE_HTTPS keys in the ConfigMap
    kubectl patch configmap domain-config -n invisible --type merge -p "{\"data\":{\"BASE_DOMAIN\":\"$base_domain\",\"USE_HTTPS\":\"$enable_https\"}}"
    
    # Restart the API deployment to pick up the new ConfigMap values
    print_info "Restarting API deployment to apply new configuration..."
    kubectl rollout restart deployment/invisible-api -n invisible
    
    # Wait for rollout to complete
    print_info "Waiting for API deployment to restart..."
    kubectl rollout status deployment/invisible-api -n invisible --timeout=120s
    
    # Verify the configuration took effect
    print_info "Verifying API configuration..."
    sleep 5  # Give the API a moment to start
    
    # Test the config endpoint
    if command -v curl &> /dev/null; then
        CONFIG_CHECK=$(curl -s "$protocol://api.$base_domain/api/config" 2>/dev/null || echo "{}")
        if echo "$CONFIG_CHECK" | grep -q "$base_domain"; then
            print_success "API configuration updated successfully - now using domain URLs"
        else
            print_warning "API may still be starting up. Check $protocol://api.$base_domain/api/config to verify domain URLs are being used."
        fi
    else
        print_success "Domain configuration ConfigMap updated successfully"
    fi
    
    print_info "Domain configuration stored in ConfigMap 'domain-config'"
    print_info "To view current configuration: kubectl get configmap domain-config -n invisible -o yaml"
}

# Setup ArgoCD ingress
setup_argocd_ingress() {
    local base_domain=$1
    local enable_https=$2
    
    print_info "Setting up ArgoCD ingress..."
    
    # Check if ArgoCD namespace exists
    if ! kubectl get namespace argocd &> /dev/null; then
        print_warning "ArgoCD namespace not found. Skipping ArgoCD ingress setup."
        return
    fi
    
    # Configure ArgoCD for insecure mode (required for ingress)
    print_info "Configuring ArgoCD for ingress access..."
    kubectl patch configmap argocd-cmd-params-cm -n argocd --type merge -p '{"data":{"server.insecure":"true"}}' 2>/dev/null || \
        kubectl create configmap argocd-cmd-params-cm -n argocd --from-literal=server.insecure=true
    
    # Create ArgoCD ingress manifest
    ARGOCD_INGRESS_FILE="/tmp/argocd-ingress.yaml"
    
    cat > "$ARGOCD_INGRESS_FILE" <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argocd-server-ingress
  namespace: argocd
  annotations:
    kubernetes.io/ingress.class: traefik
EOF
    
    if [[ "$enable_https" == "y" ]]; then
        cat >> "$ARGOCD_INGRESS_FILE" <<EOF
    cert-manager.io/cluster-issuer: letsencrypt-prod
    traefik.ingress.kubernetes.io/router.entrypoints: websecure
    traefik.ingress.kubernetes.io/router.tls: "true"
EOF
    else
        cat >> "$ARGOCD_INGRESS_FILE" <<EOF
    traefik.ingress.kubernetes.io/router.entrypoints: web
EOF
    fi
    
    cat >> "$ARGOCD_INGRESS_FILE" <<EOF
spec:
  rules:
  - host: argocd.$base_domain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argocd-server
            port:
              number: 80
EOF
    
    if [[ "$enable_https" == "y" ]]; then
        cat >> "$ARGOCD_INGRESS_FILE" <<EOF
  tls:
  - hosts:
    - argocd.$base_domain
    secretName: argocd-tls-cert
EOF
    fi
    
    # Apply ArgoCD ingress
    kubectl apply -f "$ARGOCD_INGRESS_FILE"
    
    # Restart ArgoCD server to apply insecure mode
    print_info "Restarting ArgoCD server..."
    kubectl rollout restart deployment argocd-server -n argocd
    kubectl rollout status deployment argocd-server -n argocd --timeout=120s
    
    print_success "ArgoCD ingress configured"
    print_info "ArgoCD admin password can be retrieved with:"
    echo "  kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath=\"{.data.password}\" | base64 -d"
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

# Reset to IP-based configuration
reset_to_ip_config() {
    print_header "Resetting to IP-based Configuration"
    
    print_info "Resetting domain configuration to use IP addresses..."
    
    # Get server IP
    SERVER_IP=$(kubectl get configmap server-config -n invisible -o jsonpath='{.data.SERVER_IP}')
    
    # Reset BASE_DOMAIN to empty to trigger IP-based URLs
    kubectl patch configmap domain-config -n invisible --type merge -p '{"data":{"BASE_DOMAIN":"","USE_HTTPS":"false"}}'
    
    print_info "Restarting API deployment..."
    kubectl rollout restart deployment/invisible-api -n invisible
    kubectl rollout status deployment/invisible-api -n invisible --timeout=120s
    
    print_success "Configuration reset to IP-based access"
    print_info "Services accessible at:"
    echo "  • http://$SERVER_IP:30080 (UI Hub)"
    echo "  • http://$SERVER_IP:30081 (UI Chat)"
    echo "  • http://$SERVER_IP:30084 (API)"
    echo "  • http://$SERVER_IP:30082 (Supabase)"
}

# Parse arguments
case "${1:-}" in
    status)
        show_status
        ;;
    reset)
        reset_to_ip_config
        ;;
    *)
        main
        echo ""
        print_info "Run '$0 status' to check ingress status"
        print_info "Run '$0 reset' to reset to IP-based configuration"
        ;;
esac