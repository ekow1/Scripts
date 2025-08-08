# DevOps VM Setup with GitHub Actions

This repository contains a secure VM setup script that can be deployed automatically using GitHub Actions, featuring Docker Swarm and Nginx as a reverse proxy.

## 🚀 Features

- **Conditional Deployment**: Only runs when the setup script actually changes
- **Manual Trigger**: Force deployment when needed
- **Multi-Environment Support**: Deploy to production or staging environments
- **Secure SSH Deployment**: Uses GitHub Secrets for secure access
- **Automatic Backups**: Creates backups before deployment
- **Docker Swarm**: Container orchestration with global services
- **Nginx Reverse Proxy**: Single point of entry with load balancing
- **Service Templates**: Easy service deployment with templates

## 📋 Prerequisites

### 1. VM Setup
- Ubuntu-based VM (tested on Ubuntu 20.04+)
- SSH access configured
- User with sudo privileges

### 2. GitHub Secrets Configuration

Add these secrets to your GitHub repository (`Settings` → `Secrets and variables` → `Actions`):

#### Required Secrets:
- `VM_SSH_PRIVATE_KEY`: Your private SSH key for VM access
- `PRODUCTION_VM_IP`: IP address of your production VM
- `STAGING_VM_IP`: IP address of your staging VM (optional)

#### How to generate SSH key:
```bash
# Generate SSH key pair
ssh-keygen -t rsa -b 4096 -C "github-actions@your-domain.com"

# Copy public key to VM
ssh-copy-id -i ~/.ssh/id_rsa.pub ubuntu@YOUR_VM_IP

# Copy private key content to GitHub secret
cat ~/.ssh/id_rsa
```

## 🔧 Usage

### Automatic Deployment
The workflow automatically triggers when:
- You push changes to `scripts/setup-vm-and-docker.sh`
- You push changes to the workflow file itself
- Changes are made to the `main` branch

### Manual Deployment
1. Go to your repository on GitHub
2. Navigate to `Actions` tab
3. Select "Deploy VM Setup Script"
4. Click "Run workflow"
5. Choose your options:
   - **Force deployment**: Skip change detection
   - **Target environment**: Choose production or staging

## 🛡️ Security Features

The setup script includes:
- **Firewall Configuration**: UFW with secure defaults
- **SSH Hardening**: Disabled root login and password auth
- **Fail2Ban**: Protection against brute force attacks
- **Automatic Updates**: Security updates enabled
- **Docker Installation**: Latest Docker with Swarm mode
- **Nginx Security**: Rate limiting, security headers, and SSL ready

## 📁 File Structure

```
devops/
├── .github/
│   └── workflows/
│       └── deploy-vm-setup.yml    # GitHub Actions workflow
├── scripts/
│   ├── setup-vm-and-docker.sh     # VM setup script
│   ├── create-project.sh          # Project creation script
│   ├── manage-projects.sh         # Global project manager
│   └── add-service-template.sh     # Service template generator
├── env.example                     # Environment variables example
└── README.md                       # This file
```

### **VM Structure (after deployment)**
```
/opt/
├── projects/                       # All projects
│   ├── myapp/
│   │   ├── nginx/                 # Project Nginx configs
│   │   ├── services/              # Docker Compose files
│   │   ├── ssl/                   # SSL certificates
│   │   ├── logs/                  # Application logs
│   │   └── manage-project.sh      # Project manager
│   └── other-project/
│       └── ...
├── nginx-stack.yml                # Global Nginx stack
├── manage-nginx.sh                # Nginx manager
└── backups/                       # Project backups
```

## 🌐 Dynamic Project Management with Nginx & Docker Swarm

### **Architecture Overview**
```
Internet → Nginx (Port 80/443) → Project-Specific Configs → Your Services
                ↓
        Single Point of Entry
                ↓
        Project-Based Routing
                ↓
        Service Discovery
```

### **Project-Based Structure**
```
/opt/projects/
├── project1/
│   ├── nginx/           # Project-specific Nginx configs
│   ├── services/        # Docker Compose files
│   ├── ssl/            # SSL certificates
│   ├── logs/           # Application logs
│   └── manage-project.sh
├── project2/
│   ├── nginx/
│   ├── services/
│   └── manage-project.sh
└── ...
```

### **Nginx Features**
- **Global Service**: Runs on all manager nodes
- **Reverse Proxy**: Single entry point for all applications
- **Load Balancing**: Automatic distribution across service replicas
- **SSL Ready**: Certificate management and HTTPS support
- **Security**: Rate limiting, security headers, and access control
- **Health Checks**: Automatic service health monitoring

### **Docker Swarm Features**
- **Service Discovery**: Automatic service name resolution
- **Overlay Network**: Secure communication between services
- **Rolling Updates**: Zero-downtime deployments
- **Health Monitoring**: Built-in health checks and restart policies
- **Scaling**: Easy horizontal scaling of services

### **Project Management Commands**

#### Global Project Management
```bash
# Create new project
./scripts/manage-projects.sh create myapp myapp.example.com 3000

# List all projects
./scripts/manage-projects.sh list

# Deploy all projects
./scripts/manage-projects.sh deploy-all

# Show status of all projects
./scripts/manage-projects.sh status-all

# Remove project
./scripts/manage-projects.sh remove myapp

# Backup all projects
./scripts/manage-projects.sh backup
```

#### Individual Project Management
```bash
# Navigate to project
cd /opt/projects/myapp

# Add service to project
./manage-project.sh add-service api 3001

# Deploy project
./manage-project.sh deploy

# Check project status
./manage-project.sh status

# View service logs
./manage-project.sh logs api

# Remove project
./manage-project.sh remove
```

#### Nginx Management
```bash
# Deploy Nginx stack
/opt/manage-nginx.sh deploy

# Check status
/opt/manage-nginx.sh status

# View logs
/opt/manage-nginx.sh logs

# Reload configuration
/opt/manage-nginx.sh reload
```

### **Adding New Projects & Services**

#### **Create New Project**
```bash
# Create project with domain
./scripts/manage-projects.sh create myapp myapp.example.com 3000

# This creates:
# - /opt/projects/myapp/
# - Project-specific Nginx configuration
# - Individual project manager
```

#### **Add Services to Project**
```bash
# Navigate to project
cd /opt/projects/myapp

# Add service to project
./manage-project.sh add-service api 3001
./manage-project.sh add-service web 3002
./manage-project.sh add-service admin 3003 admin.myapp.example.com

# Deploy project
./manage-project.sh deploy
```

#### **Project Structure**
Each project gets its own:
- **Nginx Configs**: `/opt/projects/<name>/nginx/`
- **Docker Compose**: `/opt/projects/<name>/services/`
- **SSL Certificates**: `/opt/projects/<name>/ssl/`
- **Management Script**: `/opt/projects/<name>/manage-project.sh`

### **SSL Configuration**
1. Place certificates in `/etc/nginx/ssl/`
2. Update Nginx configuration in `/etc/nginx/conf.d/`
3. Reload Nginx configuration

## 🔍 Monitoring

### Check Deployment Status
- View workflow runs in GitHub Actions tab
- Check VM logs: `sudo journalctl -u docker`
- Verify Docker: `docker info`
- Monitor Nginx: `/opt/manage-nginx.sh status`

### Environment Setup

#### Quick Setup
```bash
# Run the setup helper (if available)
./scripts/setup-github-secrets.sh

# Or manually generate SSH key
ssh-keygen -t rsa -b 4096 -C "github-actions@your-domain.com"

# Copy public key to VM
ssh-copy-id -i ~/.ssh/id_rsa.pub ubuntu@YOUR_VM_IP

# Test connection
ssh -i ~/.ssh/id_rsa ubuntu@YOUR_VM_IP
```

#### Environment Variables
Copy `env.example` to `.env` and configure:
```bash
# Required
VM_SSH_PRIVATE_KEY="your-private-key"
PRODUCTION_VM_IP="your-vm-ip"
STAGING_VM_IP="your-staging-ip"

# Optional
SLACK_WEBHOOK_URL="your-slack-webhook"
SMTP_USERNAME="your-email"
SMTP_PASSWORD="your-password"
```

### Troubleshooting

#### General Issues
1. **SSH Connection Issues**: Verify your SSH key is correct
2. **Permission Denied**: Ensure the VM user has sudo privileges
3. **Script Fails**: Check the workflow logs for detailed error messages

#### Docker Swarm Issues
1. **Swarm Not Initialized**: Run `docker swarm init`
2. **Service Not Starting**: Check `docker service logs <service-name>`
3. **Network Issues**: Verify overlay network exists with `docker network ls`

#### Nginx Issues
1. **Nginx Not Responding**: Check `/opt/manage-nginx.sh status`
2. **Configuration Errors**: View logs with `/opt/manage-nginx.sh logs`
3. **SSL Issues**: Verify certificates in `/etc/nginx/ssl/`
4. **Service Not Reachable**: Check service health with `docker service ls`

## ⚠️ Important Notes

- **Backup Your VM**: Always backup your VM before running the setup
- **SSH Key Security**: Keep your private key secure and never commit it to the repository
- **Firewall Rules**: The script opens ports 22 (SSH), 80 (HTTP), and 443 (HTTPS)
- **Docker Swarm**: The script initializes Docker Swarm mode
- **Nginx Configuration**: Customize `/etc/nginx/conf.d/` for your services
- **SSL Certificates**: Place certificates in `/etc/nginx/ssl/` for HTTPS
- **Service Health**: Ensure your services have `/health` endpoints for monitoring

## 🚨 Emergency Access

If you lose SSH access after deployment:
1. Use your cloud provider's console access
2. Temporarily disable the firewall: `sudo ufw disable`
3. Check SSH configuration: `sudo nano /etc/ssh/sshd_config`
4. Restart SSH: `sudo systemctl restart ssh`
