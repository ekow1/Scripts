#!/bin/bash
set -e

echo "🔐 Starting secure setup for your Google Cloud VM..."

# ------------------------------------------
# 🔒 BASIC SECURITY SETUP
# ------------------------------------------

# Update and upgrade
echo "📦 Updating system packages..."
apt update && apt -y upgrade

# Install fail2ban
echo "🛡 Installing Fail2Ban..."
apt install -y fail2ban

# Enable automatic security updates
echo "🔄 Setting up automatic security updates..."
apt install -y unattended-upgrades
dpkg-reconfigure --priority=low unattended-upgrades

# Setup UFW firewall
echo "🔥 Configuring UFW firewall..."
ufw allow OpenSSH
ufw allow http
ufw allow https
ufw default deny incoming
ufw default allow outgoing
ufw --force enable

# SSH hardening
echo "🔧 Hardening SSH configuration..."
SSH_CONFIG="/etc/ssh/sshd_config"
cp $SSH_CONFIG ${SSH_CONFIG}.bak

# Disable root login & password authentication
sed -i 's/^#*PermitRootLogin .*/PermitRootLogin no/' $SSH_CONFIG
sed -i 's/^#*PasswordAuthentication .*/PasswordAuthentication no/' $SSH_CONFIG

# Restart SSH service
echo "🔄 Restarting SSH service..."
systemctl restart ssh

# Enable fail2ban
echo "✅ Enabling and starting Fail2Ban..."
systemctl enable fail2ban
systemctl start fail2ban

echo "🔐 Basic security setup complete."
echo "🧯 Remember: If you lose your private key, you will be locked out!"

# ------------------------------------------
# 🐳 INSTALL DOCKER & INIT SWARM
# ------------------------------------------

echo "🐳 Installing Docker..."

# Install pre-requisites
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker GPG key
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Set up the Docker repo
echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" > /etc/apt/sources.list.d/docker.list

apt-get update -y

# Install Docker Engine
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start Docker
systemctl enable docker
systemctl start docker

# Add current user to docker group
usermod -aG docker $USER

echo "✅ Docker installed successfully!"

# Initialize Docker Swarm
echo "🔁 Initializing Docker Swarm..."
docker swarm init || echo "⚠️ Swarm already initialized."

# ------------------------------------------
# 🌐 NGINX SETUP FOR DOCKER SWARM
# ------------------------------------------

echo "🌐 Setting up Nginx for Docker Swarm..."

# Create overlay network for services
echo "🔗 Creating overlay network..."
docker network create --driver overlay --attachable nginx-proxy || echo "⚠️ Network already exists."

# Create Nginx configuration directory
echo "📁 Creating Nginx configuration..."
mkdir -p /etc/nginx/conf.d
mkdir -p /etc/nginx/ssl

# Create global Nginx service configuration
cat > /etc/nginx/nginx.conf << 'EOF'
user nginx;
worker_processes auto;
error_log /var/log/nginx/error.log warn;
pid /var/run/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';
    
    access_log /var/log/nginx/access.log main;
    
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 65;
    types_hash_max_size 2048;
    
    # Gzip compression
    gzip on;
    gzip_vary on;
    gzip_min_length 1024;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types
        text/plain
        text/css
        text/xml
        text/javascript
        application/json
        application/javascript
        application/xml+rss
        application/atom+xml
        image/svg+xml;
    
    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=login:10m rate=1r/s;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    add_header Content-Security-Policy "default-src 'self' http: https: data: blob: 'unsafe-inline'" always;
    
    # Include additional configurations
    include /etc/nginx/conf.d/*.conf;
}
EOF

# Create default server block
cat > /etc/nginx/conf.d/default.conf << 'EOF'
server {
    listen 80;
    server_name _;
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Default response
    location / {
        return 503 "Service temporarily unavailable\n";
        add_header Content-Type text/plain;
    }
    
    # Deny access to hidden files
    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }
}
EOF

# Create Docker Compose file for Nginx service
cat > /opt/nginx-stack.yml << 'EOF'
version: '3.8'

networks:
  nginx-proxy:
    external: true

services:
  nginx:
    image: nginx:alpine
    deploy:
      mode: global
      replicas: 1
      placement:
        constraints:
          - node.role == manager
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 120s
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /etc/nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - /etc/nginx/conf.d:/etc/nginx/conf.d:ro
      - /etc/nginx/ssl:/etc/nginx/ssl:ro
      - nginx-logs:/var/log/nginx
    networks:
      - nginx-proxy
    environment:
      - NGINX_HOST=localhost
      - NGINX_PORT=80
    healthcheck:
      test: ["CMD", "wget", "--quiet", "--tries=1", "--spider", "http://localhost/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  nginx-logs:
    driver: local
EOF

# Create service management script
cat > /opt/manage-nginx.sh << 'EOF'
#!/bin/bash

NGINX_STACK_NAME="nginx-proxy"
COMPOSE_FILE="/opt/nginx-stack.yml"

case "$1" in
    deploy)
        echo "🚀 Deploying Nginx stack..."
        docker stack deploy -c $COMPOSE_FILE $NGINX_STACK_NAME
        ;;
    remove)
        echo "🗑️ Removing Nginx stack..."
        docker stack rm $NGINX_STACK_NAME
        ;;
    logs)
        echo "📋 Showing Nginx logs..."
        docker service logs ${NGINX_STACK_NAME}_nginx
        ;;
    status)
        echo "📊 Nginx service status..."
        docker service ls | grep nginx
        docker stack services $NGINX_STACK_NAME
        ;;
    reload)
        echo "🔄 Reloading Nginx configuration..."
        docker service update --force ${NGINX_STACK_NAME}_nginx
        ;;
    *)
        echo "Usage: $0 {deploy|remove|logs|status|reload}"
        echo "  deploy  - Deploy Nginx stack"
        echo "  remove  - Remove Nginx stack"
        echo "  logs    - Show Nginx logs"
        echo "  status  - Show service status"
        echo "  reload  - Reload Nginx configuration"
        exit 1
        ;;
esac
EOF

# Make the management script executable
chmod +x /opt/manage-nginx.sh

# Create SSL certificate directory and placeholder
mkdir -p /etc/nginx/ssl
cat > /etc/nginx/ssl/README.md << 'EOF'
# SSL Certificates Directory

Place your SSL certificates here:
- private.key: Your private key
- certificate.crt: Your certificate
- ca_bundle.crt: CA bundle (if needed)

Then update your Nginx configuration in /etc/nginx/conf.d/
EOF

echo "✅ Nginx setup complete!"
echo "📋 To deploy Nginx stack: /opt/manage-nginx.sh deploy"
echo "📋 To check status: /opt/manage-nginx.sh status"
echo "🌐 Nginx will be available on ports 80 and 443"
echo "🔗 Overlay network 'nginx-proxy' created for service communication"

echo "🎉 Setup complete: VM secured + Docker & Swarm + Nginx ready!"
