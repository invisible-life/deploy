#!/bin/bash
set -e

echo "🛑 Tearing down Invisible Platform Deployment..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1"
}

print_error() {
    echo -e "${RED}[$(date +'%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[$(date +'%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1"
}

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl is not installed. Please install kubectl first."
    exit 1
fi

# Confirm teardown
if [ "$1" != "--force" ]; then
    echo "⚠️  This will delete all resources in the 'invisible' namespace!"
    echo "   Including:"
    echo "   - All running services"
    echo "   - All databases and data"
    echo "   - All secrets and configurations"
    echo ""
    read -p "Are you sure you want to continue? (yes/no): " -r
    echo
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        print_status "Teardown cancelled."
        exit 0
    fi
fi

print_status "Deleting all resources in invisible namespace..."

# Delete all resources
if kubectl get namespace invisible &> /dev/null; then
    print_status "Deleting namespace 'invisible' and all its resources..."
    kubectl delete namespace invisible --wait=true
    print_status "✅ Namespace deleted successfully"
else
    print_warning "Namespace 'invisible' does not exist"
fi

print_status "Teardown complete!"