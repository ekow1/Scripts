#!/bin/bash
set -e

# Template script for adding services to Nginx in Docker Swarm
# Usage: ./add-service-template.sh <service-name> <service-port> <domain>

SERVICE_NAME=${1:-"myapp"}
SERVICE_PORT=${2:-"3000"}
DOMAIN=${3:-"example.com"}

echo "🔧 Adding service: $SERVICE_NAME"
echo "📍 Port: $SERVICE_PORT"
echo "🌐 Domain: $DOMAIN"

# Create service configuration
cat > /etc/nginx/conf.d/${SERVICE_NAME}.conf << EOF
# Service: $SERVICE_NAME
# Port: $SERVICE_PORT
# Domain: $DOMAIN

upstream ${SERVICE_NAME}_backend {
    server ${SERVICE_NAME}:${SERVICE_PORT};
}

server {
    listen 80;
    server_name ${DOMAIN};
    
    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header X-Content-Type-Options "nosniff" always;
    
    # Rate limiting
    limit_req zone=api burst=20 nodelay;
    
    # Proxy settings
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    
    # Timeouts
    proxy_connect_timeout 60s;
    proxy_send_timeout 60s;
    proxy_read_timeout 60s;
    
    # Buffer settings
    proxy_buffering on;
    proxy_buffer_size 4k;
    proxy_buffers 8 4k;
    
    # Health check
    location /health {
        proxy_pass http://${SERVICE_NAME}_backend/health;
        access_log off;
    }
    
    # Main application
    location / {
        proxy_pass http://${SERVICE_NAME}_backend;
        
        # WebSocket support
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
    
    # Static files (if needed)
    location /static/ {
        proxy_pass http://${SERVICE_NAME}_backend/static/;
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
    
    # API endpoints
    location /api/ {
        proxy_pass http://${SERVICE_NAME}_backend/api/;
        limit_req zone=api burst=20 nodelay;
    }
}
EOF

# Create Docker Compose service template
cat > /opt/${SERVICE_NAME}-service.yml << EOF
version: '3.8'

networks:
  nginx-proxy:
    external: true

services:
  ${SERVICE_NAME}:
    image: your-app-image:latest
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
      - PORT=${SERVICE_PORT}
    networks:
      - nginx-proxy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:${SERVICE_PORT}/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    volumes:
      - ${SERVICE_NAME}-data:/app/data
    secrets:
      - ${SERVICE_NAME}_secret

volumes:
  ${SERVICE_NAME}-data:
    driver: local

secrets:
  ${SERVICE_NAME}_secret:
    external: true
EOF

# Create deployment script
cat > /opt/deploy-${SERVICE_NAME}.sh << EOF
#!/bin/bash

SERVICE_NAME="${SERVICE_NAME}"
COMPOSE_FILE="/opt/${SERVICE_NAME}-service.yml"

echo "🚀 Deploying ${SERVICE_NAME} service..."

# Deploy the service
docker stack deploy -c \$COMPOSE_FILE \$SERVICE_NAME

# Reload Nginx configuration
/opt/manage-nginx.sh reload

echo "✅ ${SERVICE_NAME} deployed successfully!"
echo "📊 Check status: docker stack services \$SERVICE_NAME"
echo "📋 View logs: docker service logs \${SERVICE_NAME}_${SERVICE_NAME}"
EOF

chmod +x /opt/deploy-${SERVICE_NAME}.sh

echo "✅ Service template created for: $SERVICE_NAME"
echo "📁 Configuration files:"
echo "   - /etc/nginx/conf.d/${SERVICE_NAME}.conf"
echo "   - /opt/${SERVICE_NAME}-service.yml"
echo "   - /opt/deploy-${SERVICE_NAME}.sh"
echo ""
echo "🚀 To deploy: /opt/deploy-${SERVICE_NAME}.sh"
echo "🔄 To reload Nginx: /opt/manage-nginx.sh reload"
