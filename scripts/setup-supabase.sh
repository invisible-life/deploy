#!/bin/bash
# Script to set up Supabase K8s manifests

echo "Setting up Supabase K8s manifests..."

# Create ConfigMap for environment variables
cat > k8s/base/supabase/configmap.yaml <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: supabase-config
  namespace: invisible
data:
  # Database
  POSTGRES_HOST: "supabase-db"
  POSTGRES_PORT: "5432"
  POSTGRES_DB: "postgres"
  
  # API URLs
  API_EXTERNAL_URL: "http://localhost:8000"
  SUPABASE_PUBLIC_URL: "http://localhost:8000"
  
  # Service URLs (internal)
  STUDIO_PG_META_URL: "http://supabase-meta:8080"
  LOGFLARE_URL: "http://supabase-analytics:4000"
  SUPABASE_URL: "http://supabase-kong:8000"
  
  # Kong Configuration
  KONG_DATABASE: "off"
  KONG_DECLARATIVE_CONFIG: "/home/kong/kong.yml"
  KONG_DNS_ORDER: "LAST,A,CNAME"
  KONG_PLUGINS: "request-transformer,cors,key-auth,acl,basic-auth"
  KONG_NGINX_PROXY_PROXY_BUFFER_SIZE: "160k"
  KONG_NGINX_PROXY_PROXY_BUFFERS: "64 160k"
  
  # Feature Flags
  NEXT_PUBLIC_ENABLE_LOGS: "true"
  NEXT_ANALYTICS_BACKEND_PROVIDER: "postgres"
  FUNCTIONS_VERIFY_JWT: "false"
  
  # Studio defaults
  STUDIO_DEFAULT_ORGANIZATION: "Default Organization"
  STUDIO_DEFAULT_PROJECT: "Default Project"
  
  # Auth settings
  SITE_URL: "http://localhost:3000"
  ADDITIONAL_REDIRECT_URLS: ""
  DISABLE_SIGNUP: "false"
  ENABLE_EMAIL_SIGNUP: "true"
  ENABLE_EMAIL_AUTOCONFIRM: "false"
  ENABLE_ANONYMOUS_USERS: "false"
  ENABLE_PHONE_SIGNUP: "true"
  ENABLE_PHONE_AUTOCONFIRM: "false"
  
  # SMTP Settings (placeholder)
  SMTP_ADMIN_EMAIL: "admin@example.com"
  SMTP_HOST: "smtp.gmail.com"
  SMTP_PORT: "587"
  SMTP_SENDER_NAME: "Supabase"
  
  # Mailer paths
  MAILER_URLPATHS_INVITE: "/auth/v1/verify"
  MAILER_URLPATHS_CONFIRMATION: "/auth/v1/verify"
  MAILER_URLPATHS_RECOVERY: "/auth/v1/verify"
  MAILER_URLPATHS_EMAIL_CHANGE: "/auth/v1/verify"
  
  # Storage
  FILE_SIZE_LIMIT: "52428800"
  STORAGE_BACKEND: "file"
  FILE_STORAGE_BACKEND_PATH: "/var/lib/storage"
  TENANT_ID: "stub"
  REGION: "stub"
  GLOBAL_S3_BUCKET: "stub"
  ENABLE_IMAGE_TRANSFORMATION: "true"
  IMGPROXY_URL: "http://supabase-imgproxy:5001"
  IMGPROXY_ENABLE_WEBP_DETECTION: "true"
  
  # Realtime
  DB_AFTER_CONNECT_QUERY: "SET search_path TO _realtime"
  DB_ENC_KEY: "supabaserealtime"
  DNS_NODES: "''"
  RLIMIT_NOFILE: "10000"
  APP_NAME: "realtime"
  SEED_SELF_HOST: "true"
  RUN_JANITOR: "true"
  
  # Analytics
  LOGFLARE_NODE_HOST: "127.0.0.1"
  DB_USERNAME: "supabase_admin"
  DB_DATABASE: "_supabase"
  DB_SCHEMA: "_analytics"
  LOGFLARE_SINGLE_TENANT: "true"
  LOGFLARE_SUPABASE_MODE: "true"
  LOGFLARE_MIN_CLUSTER_SIZE: "1"
  POSTGRES_BACKEND_SCHEMA: "_analytics"
  LOGFLARE_FEATURE_FLAG_OVERRIDE: "multibackend=true"
  
  # PostgREST
  PGRST_DB_SCHEMAS: "public,storage,graphql_public"
  PGRST_DB_ANON_ROLE: "anon"
  PGRST_DB_USE_LEGACY_GUCS: "false"
  
  # Auth (GoTrue)
  GOTRUE_API_HOST: "0.0.0.0"
  GOTRUE_API_PORT: "9999"
  GOTRUE_DB_DRIVER: "postgres"
  GOTRUE_JWT_ADMIN_ROLES: "service_role"
  GOTRUE_JWT_AUD: "authenticated"
  GOTRUE_JWT_DEFAULT_GROUP_NAME: "authenticated"
  GOTRUE_JWT_EXP: "3600"
  GOTRUE_EXTERNAL_EMAIL_ENABLED: "true"
  GOTRUE_EXTERNAL_ANONYMOUS_USERS_ENABLED: "false"
  GOTRUE_MAILER_AUTOCONFIRM: "false"
  GOTRUE_EXTERNAL_PHONE_ENABLED: "true"
  GOTRUE_SMS_AUTOCONFIRM: "false"
  
  # Edge Functions
  VERIFY_JWT: "false"
  
  # Pooler (Supavisor)
  PORT: "4000"
  POOLER_DEFAULT_POOL_SIZE: "20"
  POOLER_MAX_CLIENT_CONN: "100"
  POOLER_POOL_MODE: "transaction"
  DB_POOL_SIZE: "10"
  CLUSTER_POSTGRES: "true"
  POOLER_TENANT_ID: "local"
  REGION: "local"
  ERL_AFLAGS: "-proto_dist inet_tcp"
  
  # Imgproxy
  IMGPROXY_BIND: ":5001"
  IMGPROXY_LOCAL_FILESYSTEM_ROOT: "/"
  IMGPROXY_USE_ETAG: "true"
  
  # Meta
  PG_META_PORT: "8080"
  PG_META_DB_NAME: "postgres"
  PG_META_DB_USER: "supabase_admin"
  
  # Dashboard
  DASHBOARD_USERNAME: "supabase"
EOF

echo "ConfigMap created!"