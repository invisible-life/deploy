# Invisible Platform Scripts

This directory contains all scripts for deploying and managing the Invisible platform.

## Main Scripts

### `install-platform.sh`
**Purpose:** Main installer script that sets up the entire Invisible platform on a server.
- Installs Docker and k3s if needed
- Deploys all platform services to Kubernetes
- Auto-detects server IP for configuration
- Supports complete system reset with `--reset` flag

**Usage:**
```bash
sudo ./install-platform.sh                          # Interactive installation
sudo ./install-platform.sh --reset                  # Complete system reset
sudo ./install-platform.sh -u USERNAME -p PASSWORD  # Non-interactive mode
```

### `deploy-to-k8s.sh`
**Purpose:** Deploys the platform to an existing Kubernetes cluster.
- Used internally by `install-platform.sh`
- Creates namespaces, secrets, and applies Kubernetes manifests
- Sets up ArgoCD for GitOps management

**Usage:**
```bash
./deploy-to-k8s.sh --docker-username USER --docker-password PASS --ip SERVER_IP
```

### `generate-k8s-secrets.sh`
**Purpose:** Generates all required Kubernetes secrets for the platform.
- Creates Supabase JWT tokens and passwords
- Generates encryption keys
- Sets up application secrets

**Usage:**
```bash
DOCKER_USERNAME=user DOCKER_PASSWORD=pass ./generate-k8s-secrets.sh
```

### `setup-ingress.sh`
**Purpose:** Configure ingress routing for domain or path-based access.
- Supports domain-based routing (hub.yourdomain.com, api.yourdomain.com, etc.)
- Supports path-based routing (yourdomain.com/hub, yourdomain.com/api, etc.)
- Optional HTTPS with Let's Encrypt
- Works with K3s's built-in Traefik ingress controller

**Usage:**
```bash
./setup-ingress.sh                    # Interactive setup
./setup-ingress.sh status             # Check ingress status
```

**Requirements:**
- Existing K3s/Kubernetes cluster with Invisible platform deployed
- Domain name (for domain-based routing) or static IP
- DNS control (for domain setup)

## Utility Scripts

### `add-ssh-access.sh`
**Purpose:** Adds SSH public keys for user access to the server.
- Securely adds public SSH keys to authorized_keys
- Must be run with sudo

**Usage:**
```bash
sudo ./add-ssh-access.sh
# Then paste the public SSH key when prompted
```

### `get-auth-code.sh`
**Purpose:** Retrieves authentication codes from Mailpit for email verification.
- Fetches the latest verification code or magic link
- Works both locally and remotely

**Usage:**
```bash
./get-auth-code.sh user@example.com              # Local server
./get-auth-code.sh user@example.com 192.168.1.10 # Remote server
```

## Removed Scripts

The following scripts have been removed as part of the simplification to IP-only deployment:
- Domain configuration scripts (no longer needed - IP auto-detected)
- Docker Compose scripts (Kubernetes-only deployment)
- Individual service setup scripts (consolidated into main installer)