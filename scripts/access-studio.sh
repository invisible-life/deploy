#!/bin/bash

# =====================================================================================
#
#  Invisible - Access Supabase Studio Script
#
#  This script sets up port forwarding to access Supabase Studio locally.
#  It handles both local and remote server scenarios.
#
#  Usage:
#     ./access-studio.sh           # Local server
#     ./access-studio.sh <server>  # Remote server (IP or hostname)
#
#  Examples:
#     ./access-studio.sh                  # Access on local k3d cluster
#     ./access-studio.sh 136.243.50.116   # Access on remote server
#     ./access-studio.sh kerman.ai        # Access via SSH to domain
#
# =====================================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
NAMESPACE="invisible"
LOCAL_PORT=3000
STUDIO_PORT=3000

# Parse arguments
SERVER="${1:-local}"

echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}  Supabase Studio Access Script${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""

if [ "$SERVER" = "local" ]; then
    echo -e "${YELLOW}→ Setting up local port-forward to Supabase Studio...${NC}"
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        echo -e "${RED}✗ kubectl is not installed or not in PATH${NC}"
        exit 1
    fi
    
    # Check if the deployment exists
    if ! kubectl get deployment supabase-studio -n $NAMESPACE &> /dev/null; then
        echo -e "${RED}✗ Supabase Studio deployment not found in namespace $NAMESPACE${NC}"
        exit 1
    fi
    
    # Kill any existing port-forward on the same port
    lsof -ti:$LOCAL_PORT | xargs kill -9 2>/dev/null || true
    
    # Start port-forward
    echo -e "${GREEN}✓ Starting port-forward from localhost:$LOCAL_PORT to Studio pod...${NC}"
    kubectl port-forward -n $NAMESPACE deployment/supabase-studio $LOCAL_PORT:$STUDIO_PORT &
    
    # Give it a moment to start
    sleep 2
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Supabase Studio is now accessible at:${NC}"
    echo -e "${GREEN}  http://localhost:$LOCAL_PORT${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Press Ctrl+C to stop the tunnel${NC}"
    
    # Wait for user to stop
    wait
else
    # Remote server access
    echo -e "${YELLOW}→ Setting up SSH tunnel to remote server: $SERVER${NC}"
    
    # Check if ssh is available
    if ! command -v ssh &> /dev/null; then
        echo -e "${RED}✗ SSH is not installed${NC}"
        exit 1
    fi
    
    # Kill any existing SSH tunnel on the same port
    lsof -ti:$LOCAL_PORT | xargs kill -9 2>/dev/null || true
    
    # First, set up port-forward on the remote server
    echo -e "${YELLOW}→ Setting up port-forward on remote server...${NC}"
    ssh root@$SERVER "pkill -f 'port-forward.*supabase-studio' || true" 2>/dev/null || true
    
    # Start remote port-forward in background
    ssh root@$SERVER "kubectl port-forward -n $NAMESPACE deployment/supabase-studio $LOCAL_PORT:$STUDIO_PORT > /dev/null 2>&1 &" &
    
    # Give it a moment to start
    sleep 3
    
    # Now create SSH tunnel
    echo -e "${GREEN}✓ Creating SSH tunnel from localhost:$LOCAL_PORT to $SERVER:$LOCAL_PORT...${NC}"
    ssh -N -L $LOCAL_PORT:localhost:$LOCAL_PORT root@$SERVER &
    SSH_PID=$!
    
    # Give the tunnel a moment to establish
    sleep 2
    
    # Check if tunnel is running
    if ! kill -0 $SSH_PID 2>/dev/null; then
        echo -e "${RED}✗ Failed to establish SSH tunnel${NC}"
        exit 1
    fi
    
    echo ""
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}✓ Supabase Studio is now accessible at:${NC}"
    echo -e "${GREEN}  http://localhost:$LOCAL_PORT${NC}"
    echo ""
    echo -e "${YELLOW}Studio Credentials:${NC}"
    echo -e "${YELLOW}  Check the deployment for DASHBOARD_USERNAME and DASHBOARD_PASSWORD${NC}"
    echo -e "${YELLOW}  Default is usually: supabase / this_password_is_insecure_and_should_be_updated${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo ""
    echo -e "${YELLOW}Press Ctrl+C to stop the tunnel${NC}"
    
    # Trap Ctrl+C to clean up
    trap "echo -e '\n${YELLOW}→ Cleaning up...${NC}'; kill $SSH_PID 2>/dev/null; ssh root@$SERVER 'pkill -f \"port-forward.*supabase-studio\"' 2>/dev/null || true; exit" INT
    
    # Wait for the SSH tunnel
    wait $SSH_PID
fi