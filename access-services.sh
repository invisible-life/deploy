#!/bin/bash
# Access services through nginx ingress without modifying /etc/hosts

INGRESS_IP="172.21.0.2"

echo "Access services using curl with Host header:"
echo ""
echo "UI Hub:"
echo "  curl -H 'Host: hub.invisible.local' http://$INGRESS_IP"
echo ""
echo "Or open in browser (will require /etc/hosts entry):"
echo "  http://hub.invisible.local"
echo ""
echo "Alternative: Use port-forward to nginx controller:"
echo "  kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8080:80"
echo "  Then access: http://localhost:8080 (with Host header)"