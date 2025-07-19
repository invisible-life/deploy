#!/bin/bash
set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Invisible Platform - Secret Generation Script${NC}"
echo "=============================================="

# Check if we're in the right directory
if [ ! -f "README.md" ] || [ ! -d "k8s" ]; then
    echo -e "${RED}Error: This script must be run from the invisible-deploy root directory${NC}"
    exit 1
fi

# Function to generate random password
generate_password() {
    openssl rand -hex 32
}

# Function to generate JWT secret (min 32 chars)
generate_jwt_secret() {
    openssl rand -hex 32
}

# Function to generate JWT tokens using Node.js
generate_jwt_tokens() {
    local jwt_secret=$1
    
    # Create temporary Node.js script
    cat > /tmp/generate_jwt.js <<'EOF'
const crypto = require('crypto');

const jwtSecret = process.env.JWT_SECRET;
if (!jwtSecret) {
  console.error('JWT_SECRET environment variable not set');
  process.exit(1);
}

function base64UrlEncode(str) {
  return Buffer.from(str)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

function generateJWT(payload) {
  const header = {
    alg: 'HS256',
    typ: 'JWT'
  };
  
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  
  const signature = crypto
    .createHmac('sha256', jwtSecret)
    .update(`${encodedHeader}.${encodedPayload}`)
    .digest('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
  
  return `${encodedHeader}.${encodedPayload}.${signature}`;
}

const now = Math.floor(Date.now() / 1000);
const oneYear = 365 * 24 * 60 * 60;

const anonPayload = {
  iss: 'supabase',
  role: 'anon',
  iat: now,
  exp: now + oneYear
};

const servicePayload = {
  iss: 'supabase',
  role: 'service_role',
  iat: now,
  exp: now + oneYear
};

console.log(JSON.stringify({
  anon_key: generateJWT(anonPayload),
  service_role_key: generateJWT(servicePayload)
}));
EOF

    # Generate tokens
    JWT_SECRET=$jwt_secret node /tmp/generate_jwt.js
    rm -f /tmp/generate_jwt.js
}

# Generate all secrets
echo -e "${YELLOW}Generating secrets...${NC}"

POSTGRES_PASSWORD=$(generate_password)
JWT_SECRET=$(generate_jwt_secret)
SECRET_KEY_BASE=$(openssl rand -hex 64)
VAULT_ENC_KEY=$(generate_password)
CREDENTIALS_ENCRYPTION_KEY=$(generate_password)
DASHBOARD_PASSWORD=$(generate_password)
LOGFLARE_PUBLIC_TOKEN=$(generate_password)
LOGFLARE_PRIVATE_TOKEN=$(generate_password)

# Generate JWT tokens
echo -e "${YELLOW}Generating JWT tokens...${NC}"
JWT_TOKENS=$(generate_jwt_tokens "$JWT_SECRET")
ANON_KEY=$(echo "$JWT_TOKENS" | jq -r '.anon_key')
SERVICE_ROLE_KEY=$(echo "$JWT_TOKENS" | jq -r '.service_role_key')

# Create namespace if it doesn't exist
echo -e "${YELLOW}Creating namespace...${NC}"
kubectl create namespace invisible --dry-run=client -o yaml | kubectl apply -f -

# Create Supabase secrets
echo -e "${YELLOW}Creating Supabase secrets...${NC}"
kubectl create secret generic supabase-secrets \
  --namespace=invisible \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --from-literal=JWT_SECRET="$JWT_SECRET" \
  --from-literal=ANON_KEY="$ANON_KEY" \
  --from-literal=SERVICE_ROLE_KEY="$SERVICE_ROLE_KEY" \
  --from-literal=SECRET_KEY_BASE="$SECRET_KEY_BASE" \
  --from-literal=VAULT_ENC_KEY="$VAULT_ENC_KEY" \
  --from-literal=DASHBOARD_USERNAME="supabase" \
  --from-literal=DASHBOARD_PASSWORD="$DASHBOARD_PASSWORD" \
  --from-literal=LOGFLARE_PUBLIC_ACCESS_TOKEN="$LOGFLARE_PUBLIC_TOKEN" \
  --from-literal=LOGFLARE_PRIVATE_ACCESS_TOKEN="$LOGFLARE_PRIVATE_TOKEN" \
  --from-literal=SMTP_USER="" \
  --from-literal=SMTP_PASS="" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create application secrets
echo -e "${YELLOW}Creating application secrets...${NC}"
kubectl create secret generic app-secrets \
  --namespace=invisible \
  --from-literal=CREDENTIALS_ENCRYPTION_KEY="$CREDENTIALS_ENCRYPTION_KEY" \
  --from-literal=DOCKER_HUB_TOKEN="" \
  --from-literal=DOCKER_HUB_USERNAME="invisiblelife" \
  --dry-run=client -o yaml | kubectl apply -f -

# Save secrets to local file (for reference only - DO NOT COMMIT!)
cat > secrets.env <<EOF
# Generated on $(date)
# DO NOT COMMIT THIS FILE!

# Database
POSTGRES_PASSWORD=$POSTGRES_PASSWORD

# JWT
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY

# Encryption
SECRET_KEY_BASE=$SECRET_KEY_BASE
VAULT_ENC_KEY=$VAULT_ENC_KEY
CREDENTIALS_ENCRYPTION_KEY=$CREDENTIALS_ENCRYPTION_KEY

# Dashboard
DASHBOARD_USERNAME=supabase
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD

# Logflare
LOGFLARE_PUBLIC_ACCESS_TOKEN=$LOGFLARE_PUBLIC_TOKEN
LOGFLARE_PRIVATE_ACCESS_TOKEN=$LOGFLARE_PRIVATE_TOKEN

# Supabase URLs (update for your domain)
SUPABASE_URL=http://localhost:8000
SUPABASE_ANON_KEY=$ANON_KEY
EOF

echo -e "${GREEN}✅ Secrets generated successfully!${NC}"
echo -e "${YELLOW}Secrets saved to secrets.env (DO NOT COMMIT!)${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Update secrets.env with your SMTP credentials if needed"
echo "2. Update secrets.env with your Docker Hub token for licensing"
echo "3. Apply the ArgoCD applications: kubectl apply -f argocd/apps/app-of-apps.yaml"
echo ""
echo -e "${YELLOW}Important: Add secrets.env to .gitignore!${NC}"