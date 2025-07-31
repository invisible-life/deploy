# GitHub Actions Workflows

This directory contains GitHub Actions workflows for the invisible-deploy repository.

## Docker Build Workflow

The `docker-build.yml` workflow automatically builds and pushes the Docker image to Docker Hub when changes are pushed to the repository.

### Required Secrets

Before this workflow can run successfully, you need to add the following secrets to your GitHub repository:

1. **DOCKER_USERNAME**: Your Docker Hub username
2. **DOCKER_PASSWORD**: Your Docker Hub password or access token (recommended)

### How to Add Secrets

1. Go to your GitHub repository
2. Click on "Settings" tab
3. In the left sidebar, click on "Secrets and variables" → "Actions"
4. Click "New repository secret"
5. Add each secret:
   - Name: `DOCKER_USERNAME`
   - Value: Your Docker Hub username
   - Name: `DOCKER_PASSWORD`
   - Value: Your Docker Hub access token

### Creating a Docker Hub Access Token (Recommended)

Instead of using your Docker Hub password, it's recommended to create an access token:

1. Log in to [Docker Hub](https://hub.docker.com)
2. Click on your username → Account Settings
3. Click on "Security" → "New Access Token"
4. Give it a descriptive name (e.g., "GitHub Actions - invisible-deploy")
5. Copy the token and use it as the `DOCKER_PASSWORD` secret

### Workflow Triggers

The workflow runs on:
- Push to `main` or `master` branches
- Pull requests to `main` or `master` branches
- Manual trigger (workflow_dispatch)
- When specific files are changed (Dockerfile, scripts/, .env.example)

### Docker Image Tags

The workflow creates the following tags:
- `latest` - Always points to the latest build from the default branch
- `main` or `master` - Branch-specific tags
- `<branch>-<sha>` - Branch name with commit SHA for tracking
- Semver tags if you create releases (e.g., `v1.0.0`, `1.0`)

### Multi-Platform Support

The workflow builds images for both:
- `linux/amd64` (Intel/AMD processors)
- `linux/arm64` (ARM processors, including Apple Silicon)