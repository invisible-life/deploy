FROM alpine:3.19

# Install required tools
RUN apk add --no-cache \
    bash \
    git \
    curl \
    docker-cli \
    kubectl \
    helm \
    jq \
    sed \
    openssl \
    nodejs \
    npm && \
    # Install kustomize
    curl -s "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh" | bash && \
    mv kustomize /usr/local/bin/

# Create app directory
WORKDIR /app

# Copy all deployment files
COPY . .

# Make scripts executable
RUN chmod +x scripts/*.sh

# Set entrypoint
ENTRYPOINT ["/bin/bash"]
CMD ["scripts/setup.sh"]