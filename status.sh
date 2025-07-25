#!/bin/bash

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "📊 Invisible Platform Status"
echo "============================"
echo ""

# Check if namespace exists
if ! kubectl get namespace invisible &> /dev/null; then
    echo -e "${RED}❌ Namespace 'invisible' does not exist${NC}"
    echo "Run ./setup.sh to deploy the platform"
    exit 1
fi

# Show deployments
echo "Deployments:"
kubectl get deployments -n invisible -o wide

echo ""
echo "Pods:"
kubectl get pods -n invisible -o wide

echo ""
echo "Services:"
kubectl get services -n invisible

echo ""
echo "Pod Status Details:"
for pod in $(kubectl get pods -n invisible -o name); do
    pod_name=$(echo $pod | cut -d'/' -f2)
    status=$(kubectl get $pod -n invisible -o jsonpath='{.status.phase}')
    ready=$(kubectl get $pod -n invisible -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}')
    
    if [ "$status" = "Running" ] && [ "$ready" = "True" ]; then
        echo -e "${GREEN}✅ $pod_name${NC}"
    else
        echo -e "${RED}❌ $pod_name (Status: $status, Ready: $ready)${NC}"
        # Show recent logs for failed pods
        if [ "$status" != "Running" ] || [ "$ready" != "True" ]; then
            echo "   Recent logs:"
            kubectl logs $pod -n invisible --tail=3 2>/dev/null | sed 's/^/   /'
        fi
    fi
done

echo ""
echo "To view logs for a specific service:"
echo "  kubectl logs -l app.kubernetes.io/name=<service-name> -n invisible --tail=50"