#!/bin/bash
set -e

# Script to configure production access method
# Usage: ./configure-access.sh [domain|nodeport] [domain-name]

ACCESS_METHOD=${1:-nodeport}
DOMAIN_NAME=${2:-}

echo "🔧 Configuring production access method: $ACCESS_METHOD"

# Path to production kustomization
KUSTOMIZATION_FILE="k8s/overlays/production/kustomization.yaml"

case $ACCESS_METHOD in
  domain)
    if [ -z "$DOMAIN_NAME" ]; then
      echo "❌ Error: Domain name required for domain access method"
      echo "Usage: $0 domain your-domain.com"
      exit 1
    fi
    
    echo "📝 Configuring domain-based access for: $DOMAIN_NAME"
    
    # Update ingress with actual domain
    sed -i.bak "s/invisible.life/$DOMAIN_NAME/g" k8s/overlays/production/ingress.yaml
    
    # Update kustomization to use ingress
    sed -i.bak '
      s|# - ingress.yaml|- ingress.yaml|
      s|# - cert-issuer.yaml|- cert-issuer.yaml|
      s|- ingress-nodeport.yaml|# - ingress-nodeport.yaml|
    ' $KUSTOMIZATION_FILE
    
    echo "✅ Domain access configured"
    echo ""
    echo "Next steps:"
    echo "1. Update DNS records to point to your cluster:"
    echo "   - app.$DOMAIN_NAME → Cluster IP/Load Balancer"
    echo "   - chat.$DOMAIN_NAME → Cluster IP/Load Balancer"
    echo "   - api.$DOMAIN_NAME → Cluster IP/Load Balancer"
    echo "2. Install cert-manager if not already installed"
    echo "3. Deploy with: ./setup.sh production"
    ;;
    
  nodeport)
    echo "📝 Configuring NodePort access (no domain required)"
    
    # Update kustomization to use nodeport
    sed -i.bak '
      s|- ingress.yaml|# - ingress.yaml|
      s|- cert-issuer.yaml|# - cert-issuer.yaml|
      s|# - ingress-nodeport.yaml|- ingress-nodeport.yaml|
    ' $KUSTOMIZATION_FILE
    
    echo "✅ NodePort access configured"
    echo ""
    echo "After deployment, access services at:"
    echo "   - UI Hub: http://YOUR_SERVER_IP:30080"
    echo "   - UI Chat: http://YOUR_SERVER_IP:30081"
    echo "   - API: http://YOUR_SERVER_IP:30082"
    ;;
    
  *)
    echo "❌ Error: Invalid access method. Use 'domain' or 'nodeport'"
    exit 1
    ;;
esac

# Clean up backup files
rm -f k8s/overlays/production/*.bak