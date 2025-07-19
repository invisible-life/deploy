#!/bin/bash
set -euo pipefail

echo "🚀 Setting up Supabase with Docker Compose..."

# Create supabase directory
mkdir -p supabase
cd supabase

# Download official Supabase files
echo "📥 Downloading Supabase docker-compose..."
curl -o docker-compose.yml https://raw.githubusercontent.com/supabase/supabase/master/docker/docker-compose.yml
curl -o .env.example https://raw.githubusercontent.com/supabase/supabase/master/docker/.env.example

# Copy volumes directory from orchestrator if it exists
if [ -d "../../invisible-orchestrator/volumes" ]; then
    echo "📁 Copying volumes from orchestrator..."
    cp -r ../../invisible-orchestrator/volumes .
fi

# Generate secrets if .env doesn't exist
if [ ! -f ".env" ]; then
    echo "🔐 Generating .env file..."
    
    # Generate passwords and tokens
    POSTGRES_PASSWORD=$(openssl rand -hex 32)
    JWT_SECRET=$(openssl rand -hex 32)
    DASHBOARD_PASSWORD=$(openssl rand -hex 16)
    
    # Generate JWT tokens using Node.js
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

console.log('ANON_KEY=' + generateJWT(anonPayload));
console.log('SERVICE_ROLE_KEY=' + generateJWT(servicePayload));
EOF

    # Generate JWT tokens
    JWT_OUTPUT=$(JWT_SECRET=$JWT_SECRET node /tmp/generate_jwt.js)
    ANON_KEY=$(echo "$JWT_OUTPUT" | grep ANON_KEY | cut -d'=' -f2)
    SERVICE_ROLE_KEY=$(echo "$JWT_OUTPUT" | grep SERVICE_ROLE_KEY | cut -d'=' -f2)
    rm -f /tmp/generate_jwt.js

    # Create .env file
    cat > .env <<EOF
############
# Secrets
############

POSTGRES_PASSWORD=$POSTGRES_PASSWORD
JWT_SECRET=$JWT_SECRET
ANON_KEY=$ANON_KEY
SERVICE_ROLE_KEY=$SERVICE_ROLE_KEY
DASHBOARD_USERNAME=supabase
DASHBOARD_PASSWORD=$DASHBOARD_PASSWORD

############
# Database
############

POSTGRES_HOST=db
POSTGRES_PORT=5432
POSTGRES_DB=postgres

############
# API Proxy
############

KONG_HTTP_PORT=8000
KONG_HTTPS_PORT=8443

############
# API
############

PGRST_DB_SCHEMAS=public,storage,graphql_public
PGRST_DB_ANON_ROLE=anon
PGRST_DB_USE_LEGACY_GUCS=false

############
# Auth
############

SITE_URL=http://localhost:3000
ADDITIONAL_REDIRECT_URLS=
JWT_EXPIRY=3600
DISABLE_SIGNUP=false
API_EXTERNAL_URL=http://localhost:8000
MAILER_URLPATHS_INVITE=/auth/v1/verify
MAILER_URLPATHS_CONFIRMATION=/auth/v1/verify
MAILER_URLPATHS_RECOVERY=/auth/v1/verify
MAILER_URLPATHS_EMAIL_CHANGE=/auth/v1/verify

############
# Logs
############

LOGFLARE_PUBLIC_ACCESS_TOKEN=$(openssl rand -hex 16)
LOGFLARE_PRIVATE_ACCESS_TOKEN=$(openssl rand -hex 16)

############
# Studio
############

STUDIO_DEFAULT_ORGANIZATION=Default
STUDIO_DEFAULT_PROJECT=Default
SUPABASE_PUBLIC_URL=http://localhost:8000

############
# Email / SMS
############

ENABLE_EMAIL_SIGNUP=true
ENABLE_EMAIL_AUTOCONFIRM=false
SMTP_ADMIN_EMAIL=admin@example.com
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_SENDER_NAME=Supabase
ENABLE_PHONE_SIGNUP=false
ENABLE_PHONE_AUTOCONFIRM=false
ENABLE_ANONYMOUS_USERS=false

############
# Storage
############

STORAGE_BACKEND=file
FILE_SIZE_LIMIT=52428800

############
# Other
############

SECRET_KEY_BASE=$(openssl rand -hex 64)
VAULT_ENC_KEY=$(openssl rand -hex 32)
FUNCTIONS_VERIFY_JWT=false
IMGPROXY_ENABLE_WEBP_DETECTION=true
POOLER_DEFAULT_POOL_SIZE=20
POOLER_MAX_CLIENT_CONN=100
POOLER_TENANT_ID=local
POOLER_DB_POOL_SIZE=10
DOCKER_SOCKET_LOCATION=/var/run/docker.sock
EOF
    
    echo "✅ Generated .env file with secrets"
    echo ""
    echo "🔑 Important credentials:"
    echo "Dashboard: http://localhost:8000/project/default"
    echo "Username: supabase"
    echo "Password: $DASHBOARD_PASSWORD"
    echo ""
    echo "Anon Key: $ANON_KEY"
    echo "Service Role Key: $SERVICE_ROLE_KEY"
else
    echo "✅ Using existing .env file"
fi

# Start Supabase
echo "🐳 Starting Supabase..."
docker compose up -d

echo ""
echo "✅ Supabase is starting up!"
echo ""
echo "Access points:"
echo "- Studio: http://localhost:8000"
echo "- API: http://localhost:8000"
echo "- DB: localhost:5432"
echo ""
echo "Check status: docker compose ps"
echo "View logs: docker compose logs -f"
echo "Stop: docker compose down"
echo "Destroy: docker compose down -v"