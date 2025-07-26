#!/bin/bash
set -e

# Script to enable local access to services
echo "🚀 Setting up local access to Invisible Platform services..."

# Kill any existing port-forwards
echo "Cleaning up existing port-forwards..."
pkill -f "kubectl port-forward" 2>/dev/null || true

# Start port-forwards in background
echo ""
echo "Starting port-forwards..."
echo "  - UI Hub: http://localhost:8080"
kubectl port-forward service/ui-hub 8080:80 -n invisible > /dev/null 2>&1 &

echo "  - UI Chat: http://localhost:8081"
kubectl port-forward service/ui-chat 8081:80 -n invisible > /dev/null 2>&1 &

echo "  - API Gateway: http://localhost:8082"
kubectl port-forward service/supabase-kong 8082:8000 -n invisible > /dev/null 2>&1 &

echo "  - Backend API: http://localhost:4300"
kubectl port-forward service/invisible-api 4300:4300 -n invisible > /dev/null 2>&1 &

echo ""
echo "✅ Services are now accessible!"
echo ""
echo "Access points:"
echo "  - UI Hub:      http://localhost:8080"
echo "  - UI Chat:     http://localhost:8081"
echo "  - API Gateway: http://localhost:8082"
echo "  - Backend API: http://localhost:4300"
echo ""
echo "Press Ctrl+C to stop all port-forwards"

# Wait for Ctrl+C
trap "echo 'Stopping port-forwards...'; pkill -f 'kubectl port-forward'; exit" INT
while true; do sleep 1; done