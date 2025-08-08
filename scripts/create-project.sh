#!/bin/bash
set -e

# Project creation script for dynamic service management
# Usage: ./create-project.sh <project-name> <domain> [port]

PROJECT_NAME=${1:-"myproject"}
DOMAIN=${2:-"example.com"}
DEFAULT_PORT=${3:-"3000"}

echo "🚀 Creating project: $PROJECT_NAME"
echo "🌐 Domain: $DOMAIN"
echo "📍 Default port: $DEFAULT_PORT"

# Create project directory structure
PROJECT_DIR="/opt/projects/$PROJECT_NAME"
mkdir -p "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR/nginx"
mkdir -p "$PROJECT_DIR/services"
mkdir -p "$PROJECT_DIR/ssl"
mkdir -p "$PROJECT_DIR/logs"

echo "📁 Creating project structure in $PROJECT_DIR"

# Create project-specific Nginx configuration
cat > "$PROJECT_DIR/nginx/nginx.conf" << EOF
# Nginx configuration for $PROJECT_NAME
# Domain: $DOMAIN

server {
    listen 80;
    server_name $DOMAIN;
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "no-referrer-when-downgrade" always;
    
    # Rate limiting
    limit_req_zone \$binary_remote_addr zone=api:10m rate=10r/s;
    limit_req zone=api burst=20 nodelay;
    
    # Health check
    location /health {
        access_log off;
        return 200 "healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Include service configurations
    include /etc/nginx/conf.d/$PROJECT_NAME/*.conf;
    
    # Default response
    location / {
        return 503 "Service temporarily unavailable\n";
        add_header Content-Type text/plain;
    }
}

# SSL configuration (uncomment when certificates are ready)
# server {
#     listen 443 ssl http2;
#     server_name $DOMAIN;
#     
#     ssl_certificate /opt/projects/$PROJECT_NAME/ssl/certificate.crt;
#     ssl_certificate_key /opt/projects/$PROJECT_NAME/ssl/private.key;
#     
#     include /etc/nginx/conf.d/$PROJECT_NAME/*.conf;
# }
EOF

# Create project management script
cat > "$PROJECT_DIR/manage-project.sh" << EOF
#!/bin/bash

PROJECT_NAME="$PROJECT_NAME"
PROJECT_DIR="$PROJECT_DIR"
DOMAIN="$DOMAIN"

case "\$1" in
    add-service)
        SERVICE_NAME=\$2
        SERVICE_PORT=\$3
        SERVICE_DOMAIN=\$4
        
        if [ -z "\$SERVICE_NAME" ] || [ -z "\$SERVICE_PORT" ]; then
            echo "Usage: \$0 add-service <service-name> <port> [subdomain]"
            exit 1
        fi
        
        # Create service configuration
        cat > "\$PROJECT_DIR/nginx/\$SERVICE_NAME.conf" << 'SERVICE_EOF'
# Service: \$SERVICE_NAME
# Port: \$SERVICE_PORT
# Domain: \${SERVICE_DOMAIN:-$DOMAIN}

upstream \${SERVICE_NAME}_backend {
    server \${SERVICE_NAME}:\${SERVICE_PORT};
}

server {
    listen 80;
    server_name \${SERVICE_DOMAIN:-$DOMAIN};
    
    # Proxy settings
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    
    # Timeouts
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    
    # Health check
    location /health {
        proxy_pass http://\${SERVICE_NAME}_backend/health;
        access_log off;
    }
    
    # Main application
    location / {
        proxy_pass http://\${SERVICE_NAME}_backend;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # API endpoints
    location /api/ {
        proxy_pass http://\${SERVICE_NAME}_backend/api/;
        limit_req zone=api burst=20 nodelay;
    }
}
SERVICE_EOF
        
        # Create Docker Compose service
        cat > "\$PROJECT_DIR/services/\$SERVICE_NAME.yml" << 'COMPOSE_EOF'
version: '3.8'

networks:
  nginx-proxy:
    external: true

services:
  \${SERVICE_NAME}:
    image: your-\${SERVICE_NAME}-image:latest
    deploy:
      replicas: 2
      restart_policy:
        condition: on-failure
        delay: 5s
        max_attempts: 3
        window: 120s
      update_config:
        parallelism: 1
        delay: 10s
        order: start-first
    environment:
      - NODE_ENV=production
      - PORT=\${SERVICE_PORT}
    networks:
      - nginx-proxy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:\${SERVICE_PORT}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    volumes:
      - \${SERVICE_NAME}-data:/app/data
COMPOSE_EOF
        
        # Create deployment script
        cat > "\$PROJECT_DIR/deploy-\$SERVICE_NAME.sh" << 'DEPLOY_EOF'
#!/bin/bash

SERVICE_NAME="\${SERVICE_NAME}"
COMPOSE_FILE="\$PROJECT_DIR/services/\$SERVICE_NAME.yml"

echo "🚀 Deploying \$SERVICE_NAME service..."

# Deploy the service
docker stack deploy -c \$COMPOSE_FILE \$SERVICE_NAME

# Copy Nginx configuration
cp "\$PROJECT_DIR/nginx/\$SERVICE_NAME.conf" /etc/nginx/conf.d/$PROJECT_NAME/

# Reload Nginx
/opt/manage-nginx.sh reload

echo "✅ \$SERVICE_NAME deployed successfully!"
echo "📊 Check status: docker stack services \$SERVICE_NAME"
echo "📋 View logs: docker service logs \${SERVICE_NAME}_\${SERVICE_NAME}"
DEPLOY_EOF
        
        chmod +x "\$PROJECT_DIR/deploy-\$SERVICE_NAME.sh"
        
        echo "✅ Service \$SERVICE_NAME added to project \$PROJECT_NAME"
        echo "📁 Configuration: \$PROJECT_DIR/nginx/\$SERVICE_NAME.conf"
        echo "🚀 Deploy with: \$PROJECT_DIR/deploy-\$SERVICE_NAME.sh"
        ;;
        
    deploy)
        echo "🚀 Deploying project \$PROJECT_NAME..."
        
        # Copy project Nginx configuration
        mkdir -p /etc/nginx/conf.d/$PROJECT_NAME
        cp "\$PROJECT_DIR/nginx/"*.conf /etc/nginx/conf.d/$PROJECT_NAME/ 2>/dev/null || true
        
        # Deploy all services
        for service_file in "\$PROJECT_DIR/services/"*.yml; do
            if [ -f "\$service_file" ]; then
                service_name=\$(basename "\$service_file" .yml)
                echo "📦 Deploying \$service_name..."
                docker stack deploy -c "\$service_file" "\$service_name"
            fi
        done
        
        # Reload Nginx
        /opt/manage-nginx.sh reload
        
        echo "✅ Project \$PROJECT_NAME deployed successfully!"
        ;;
        
    remove)
        echo "🗑️ Removing project \$PROJECT_NAME..."
        
        # Remove all services
        for service_file in "\$PROJECT_DIR/services/"*.yml; do
            if [ -f "\$service_file" ]; then
                service_name=\$(basename "\$service_file" .yml)
                echo "🗑️ Removing \$service_name..."
                docker stack rm "\$service_name"
            fi
        done
        
        # Remove Nginx configuration
        rm -rf /etc/nginx/conf.d/$PROJECT_NAME
        
        # Reload Nginx
        /opt/manage-nginx.sh reload
        
        echo "✅ Project \$PROJECT_NAME removed successfully!"
        ;;
        
    status)
        echo "📊 Project \$PROJECT_NAME status:"
        echo "=================================="
        
        # Show services
        for service_file in "\$PROJECT_DIR/services/"*.yml; do
            if [ -f "\$service_file" ]; then
                service_name=\$(basename "\$service_file" .yml)
                echo "📦 \$service_name:"
                docker stack services "\$service_name" 2>/dev/null || echo "  Not deployed"
            fi
        done
        
        echo ""
        echo "🌐 Nginx configuration:"
        ls -la /etc/nginx/conf.d/$PROJECT_NAME/ 2>/dev/null || echo "  No configuration found"
        ;;
        
    logs)
        SERVICE_NAME=\$2
        if [ -z "\$SERVICE_NAME" ]; then
            echo "Usage: \$0 logs <service-name>"
            exit 1
        fi
        
        echo "📋 Logs for \$SERVICE_NAME:"
        docker service logs "\$SERVICE_NAME_\$SERVICE_NAME"
        ;;
        
    *)
        echo "Usage: \$0 {add-service|deploy|remove|status|logs}"
        echo ""
        echo "Commands:"
        echo "  add-service <name> <port> [subdomain]  - Add new service to project"
        echo "  deploy                                  - Deploy all project services"
        echo "  remove                                  - Remove all project services"
        echo "  status                                  - Show project status"
        echo "  logs <service-name>                     - Show service logs"
        echo ""
        echo "Project: \$PROJECT_NAME"
        echo "Domain: \$DOMAIN"
        echo "Directory: \$PROJECT_DIR"
        exit 1
        ;;
esac
EOF

chmod +x "$PROJECT_DIR/manage-project.sh"

# Create project README
cat > "$PROJECT_DIR/README.md" << EOF
# Project: $PROJECT_NAME

## Overview
- **Domain**: $DOMAIN
- **Directory**: $PROJECT_DIR
- **Default Port**: $DEFAULT_PORT

## Quick Start

### 1. Add a Service
\`\`\`bash
$PROJECT_DIR/manage-project.sh add-service myapp 3000
\`\`\`

### 2. Deploy Project
\`\`\`bash
$PROJECT_DIR/manage-project.sh deploy
\`\`\`

### 3. Check Status
\`\`\`bash
$PROJECT_DIR/manage-project.sh status
\`\`\`

## Directory Structure
\`\`\`
$PROJECT_DIR/
├── nginx/           # Nginx configurations
├── services/        # Docker Compose files
├── ssl/            # SSL certificates
├── logs/           # Application logs
└── manage-project.sh
\`\`\`

## SSL Setup
1. Place certificates in \`$PROJECT_DIR/ssl/\`
2. Update \`$PROJECT_DIR/nginx/nginx.conf\`
3. Reload Nginx: \`/opt/manage-nginx.sh reload\`

## Services
Add services using:
\`\`\`bash
$PROJECT_DIR/manage-project.sh add-service <name> <port> [subdomain]
\`\`\`

Each service will get:
- Nginx configuration: \`$PROJECT_DIR/nginx/<name>.conf\`
- Docker Compose: \`$PROJECT_DIR/services/<name>.yml\`
- Deployment script: \`$PROJECT_DIR/deploy-<name>.sh\`
EOF

echo "✅ Project $PROJECT_NAME created successfully!"
echo ""
echo "📁 Project directory: $PROJECT_DIR"
echo "🚀 Manage project: $PROJECT_DIR/manage-project.sh"
echo ""
echo "Quick commands:"
echo "  Add service: $PROJECT_DIR/manage-project.sh add-service myapp 3000"
echo "  Deploy: $PROJECT_DIR/manage-project.sh deploy"
echo "  Status: $PROJECT_DIR/manage-project.sh status"
