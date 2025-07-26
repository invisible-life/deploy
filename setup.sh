#!/bin/bash
set -e

# Script usage
usage() {
    echo "Usage: $0 [OPTIONS] [environment]"
    echo ""
    echo "Environments:"
    echo "  dev          Deploy development environment (default)"
    echo "  production   Deploy production environment"
    echo "  base         Deploy base configuration only"
    echo ""
    echo "Options:"
    echo "  --docker-username <username>   Docker Hub username"
    echo "  --docker-password <password>   Docker Hub password/token"
    echo "  --help                         Show this help message"
    echo ""
    echo "Example:"
    echo "  $0                                          # Deploy dev environment"
    echo "  $0 production                               # Deploy production"
    echo "  $0 --docker-username myuser --docker-password mytoken dev"
    echo ""
    echo "Note: Docker credentials can also be set via environment variables:"
    echo "  DOCKER_USERNAME and DOCKER_PASSWORD"
    exit 1
}

# Default environment
ENVIRONMENT="dev"

# Parse command line arguments
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
        --help)
            usage
            ;;
        base|dev|production)
            ENVIRONMENT="$1"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

echo "🚀 Starting Invisible Platform Deployment - $ENVIRONMENT environment"

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

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Check if we're in the right directory or use SCRIPT_DIR
if [ -f "k8s/base/kustomization.yaml" ]; then
    # Running from the correct directory
    BASE_DIR="."
elif [ -f "$SCRIPT_DIR/k8s/base/kustomization.yaml" ]; then
    # Script called from elsewhere, use script directory
    BASE_DIR="$SCRIPT_DIR"
    cd "$BASE_DIR"
else
    print_error "Cannot find k8s/base/kustomization.yaml. Please ensure you're in the invisible-deploy directory"
    exit 1
fi

print_status "Working directory: $(pwd)"

print_status "Creating namespace..."
kubectl create namespace invisible --dry-run=client -o yaml | kubectl apply -f -

print_status "Creating secrets..."
# Create Supabase secrets if they don't exist
if ! kubectl get secret supabase-secrets -n invisible &> /dev/null; then
    print_status "Creating Supabase secrets..."
    
    # Use environment-specific values if available
    case $ENVIRONMENT in
        production)
            # Production should use strong, unique passwords
            POSTGRES_PASSWORD=${PROD_POSTGRES_PASSWORD:-$(openssl rand -hex 32)}
            JWT_SECRET=${PROD_JWT_SECRET:-$(openssl rand -hex 32)}
            ;;
        *)
            # Dev/base can use default passwords
            POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-$(openssl rand -hex 32)}
            JWT_SECRET=${JWT_SECRET:-$(openssl rand -hex 32)}
            ;;
    esac
    
    ANON_KEY=${ANON_KEY:-"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJhbm9uIiwiaWF0IjoxNzUzNDc2Njk2LCJleHAiOjE3ODUwMTI2OTZ9.mw3T0SbIczmTs9JIg0xS3JLsLlsn4ABtNLwtq90PRzM"}
    SERVICE_ROLE_KEY=${SERVICE_ROLE_KEY:-"eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJvbGUiOiJzZXJ2aWNlX3JvbGUiLCJpYXQiOjE3NTM0NzY2OTYsImV4cCI6MTc4NTAxMjY5Nn0.C9HpOUpksBk5n-1cpLC22hrXM47Qq30S4474l13mHgQ"}
    
    kubectl create secret generic supabase-secrets \
        --from-literal=POSTGRES_PASSWORD=$POSTGRES_PASSWORD \
        --from-literal=JWT_SECRET=$JWT_SECRET \
        --from-literal=ANON_KEY=$ANON_KEY \
        --from-literal=SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY \
        -n invisible
else
    print_warning "Supabase secrets already exist, skipping..."
fi

# Create app secrets if they don't exist
if ! kubectl get secret app-secrets -n invisible &> /dev/null; then
    print_status "Creating app secrets..."
    print_warning "Consider running scripts/generate-secrets.sh for proper secret generation"
    
    CREDENTIALS_ENCRYPTION_KEY=${CREDENTIALS_ENCRYPTION_KEY:-$(openssl rand -hex 32)}
    
    kubectl create secret generic app-secrets \
        --from-literal=CREDENTIALS_ENCRYPTION_KEY=$CREDENTIALS_ENCRYPTION_KEY \
        -n invisible
else
    print_warning "App secrets already exist, skipping..."
fi

# Create Docker Hub secret if needed
if ! kubectl get secret dockerhub-secret -n invisible &> /dev/null; then
    if [ -n "$DOCKER_USERNAME" ] && [ -n "$DOCKER_PASSWORD" ]; then
        print_status "Creating Docker Hub secret..."
        kubectl create secret docker-registry dockerhub-secret \
            --docker-server=docker.io \
            --docker-username=$DOCKER_USERNAME \
            --docker-password=$DOCKER_PASSWORD \
            -n invisible
    else
        print_warning "DOCKER_USERNAME and DOCKER_PASSWORD not set, skipping Docker Hub secret creation"
        print_warning "Private images may fail to pull"
    fi
else
    print_warning "Docker Hub secret already exists, skipping..."
fi

print_status "Applying Kubernetes manifests..."

# Apply the appropriate configuration
case $ENVIRONMENT in
    base)
        print_status "Applying base configuration..."
        kubectl apply -k k8s/base/
        ;;
    dev)
        print_status "Applying development configuration..."
        kubectl apply -k k8s/overlays/dev/
        ;;
    production)
        print_status "Applying production configuration..."
        kubectl apply -k k8s/overlays/production/
        ;;
esac

# Wait for critical services
print_status "Waiting for PostgreSQL to be ready..."
# First wait for pod to exist
while ! kubectl get pods -l app.kubernetes.io/component=database -n invisible 2>/dev/null | grep -q postgres; do
    echo -n "."
    sleep 2
done
echo ""

# Then wait for it to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=database -n invisible --timeout=300s || {
    print_error "PostgreSQL failed to start"
    print_status "Pod status:"
    kubectl get pods -l app.kubernetes.io/component=database -n invisible
    print_status "Pod logs:"
    kubectl logs -l app.kubernetes.io/component=database -n invisible --tail=50
    exit 1
}

print_status "Waiting for ETL to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=invisible-etl -n invisible --timeout=300s || {
    print_error "ETL failed to start"
    kubectl logs -l app.kubernetes.io/name=invisible-etl -n invisible --tail=50
    exit 1
}

print_status "Waiting for Auth service to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=supabase-auth -n invisible --timeout=300s || {
    print_error "Auth service failed to start"
    kubectl logs -l app.kubernetes.io/name=supabase-auth -n invisible --tail=50
    exit 1
}

# Check all deployments
print_status "Checking deployment status..."
kubectl get deployments -n invisible

# Show all pods
print_status "All pods:"
kubectl get pods -n invisible

# Show services
print_status "All services:"
kubectl get services -n invisible

print_status "✅ Deployment complete!"
print_status ""
print_status "Environment: $ENVIRONMENT"
print_status "To check the status of your deployment:"
print_status "  kubectl get pods -n invisible"
print_status ""
print_status "To view logs for a specific service:"
print_status "  kubectl logs -l app.kubernetes.io/name=<service-name> -n invisible"
print_status ""

# Environment-specific access instructions
case $ENVIRONMENT in
    dev)
        print_status "To access the services locally:"
        print_status "  - UI Hub: http://hub.invisible.local"
        print_status "  - UI Chat: http://chat.invisible.local"
        print_status "  - API: http://api.invisible.local"
        print_status ""
        print_status "Make sure to add these to /etc/hosts pointing to 127.0.0.1"
        ;;
    production)
        print_status "To configure production access:"
        print_status "  Option 1 (with domain): ./scripts/configure-access.sh domain your-domain.com"
        print_status "  Option 2 (IP:PORT):     ./scripts/configure-access.sh nodeport"
        print_status ""
        print_status "Then redeploy with: ./setup.sh production"
        ;;
    *)
        print_status "To access the services:"
        print_status "  - PostgreSQL: supabase-db:5432"
        print_status "  - Kong API Gateway: supabase-kong:8000"
        print_status "  - ETL Service: invisible-etl:4001"
        print_status "  - API Service: invisible-api:4300"
        ;;
esac