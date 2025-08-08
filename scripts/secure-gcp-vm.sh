#!/bin/bash

# GCP VM Security Hardening Script
# This script secures your GCP VM with best practices

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    print_error "gcloud CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    print_error "You are not authenticated with gcloud. Please run 'gcloud auth login' first."
    exit 1
fi

print_status "Starting GCP VM Security Hardening..."

# Get current project and VM details
PROJECT_ID=$(gcloud config get-value project)
print_status "Using project: $PROJECT_ID"

# Get VM details (assuming we're running this from the VM)
VM_NAME=$(hostname)
ZONE=$(curl -H "Metadata-Flavor: Google" http://metadata.google.internal/computeMetadata/v1/instance/zone 2>/dev/null | cut -d/ -f4)
REGION=$(echo $ZONE | sed 's/-[a-z]$//')

print_status "VM Name: $VM_NAME"
print_status "Zone: $ZONE"
print_status "Region: $REGION"

# Get current external IP
CURRENT_IP=$(curl -s ifconfig.me)
print_status "Current external IP: $CURRENT_IP"

# Function to create firewall rules
create_firewall_rules() {
    print_status "Creating firewall rules..."
    
    # Create restrictive SSH rule
    if ! gcloud compute firewall-rules describe allow-ssh-restricted --project=$PROJECT_ID &>/dev/null; then
        gcloud compute firewall-rules create allow-ssh-restricted \
            --allow tcp:22 \
            --source-ranges $CURRENT_IP/32 \
            --description "Allow SSH from current IP only" \
            --project=$PROJECT_ID
        print_success "Created restrictive SSH firewall rule"
    else
        print_warning "SSH firewall rule already exists"
    fi
    
    # Create web traffic rule
    if ! gcloud compute firewall-rules describe allow-web --project=$PROJECT_ID &>/dev/null; then
        gcloud compute firewall-rules create allow-web \
            --allow tcp:80,tcp:443 \
            --source-ranges 0.0.0.0/0 \
            --description "Allow web traffic" \
            --project=$PROJECT_ID
        print_success "Created web traffic firewall rule"
    else
        print_warning "Web traffic firewall rule already exists"
    fi
    
    # Remove default allow rules (be careful!)
    print_warning "Removing default allow rules..."
    gcloud compute firewall-rules delete default-allow-ssh --project=$PROJECT_ID --quiet 2>/dev/null || true
    gcloud compute firewall-rules delete default-allow-rdp --project=$PROJECT_ID --quiet 2>/dev/null || true
    gcloud compute firewall-rules delete default-allow-internal --project=$PROJECT_ID --quiet 2>/dev/null || true
    print_success "Removed default allow rules"
}

# Function to harden SSH
harden_ssh() {
    print_status "Hardening SSH configuration..."
    
    # Backup original SSH config
    sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup.$(date +%Y%m%d_%H%M%S)
    
    # Disable password authentication
    sudo sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    sudo sed -i 's/PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config
    
    # Disable root login
    sudo sed -i 's/#PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    
    # Set SSH port to 22 (keep default for now)
    # sudo sed -i 's/#Port 22/Port 2222/' /etc/ssh/sshd_config
    
    # Restart SSH service
    sudo systemctl restart ssh
    
    print_success "SSH hardened successfully"
}

# Function to install and configure fail2ban
setup_fail2ban() {
    print_status "Installing and configuring fail2ban..."
    
    # Install fail2ban
    sudo apt update
    sudo apt install -y fail2ban
    
    # Create fail2ban configuration
    sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
    
    # Configure fail2ban for SSH
    sudo tee -a /etc/fail2ban/jail.local > /dev/null <<EOF

[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600
findtime = 600
EOF
    
    # Enable and start fail2ban
    sudo systemctl enable fail2ban
    sudo systemctl start fail2ban
    
    print_success "fail2ban installed and configured"
}

# Function to setup automatic security updates
setup_auto_updates() {
    print_status "Setting up automatic security updates..."
    
    # Install unattended-upgrades
    sudo apt install -y unattended-upgrades
    
    # Configure unattended-upgrades
    sudo tee /etc/apt/apt.conf.d/50unattended-upgrades > /dev/null <<EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
    "\${distro_id}ESMApps:\${distro_codename}-apps-security";
    "\${distro_id}ESM:\${distro_codename}-infra-security";
};
Unattended-Upgrade::Package-Blacklist {
};
Unattended-Upgrade::DevRelease "false";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
EOF
    
    # Enable automatic updates
    sudo tee /etc/apt/apt.conf.d/20auto-upgrades > /dev/null <<EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
    
    print_success "Automatic security updates configured"
}

# Function to install monitoring tools
setup_monitoring() {
    print_status "Setting up monitoring tools..."
    
    # Install basic monitoring tools
    sudo apt install -y htop iotop nethogs net-tools
    
    # Install Google Cloud Ops Agent
    if ! command -v google-cloud-ops-agent &> /dev/null; then
        curl -sSO https://dl.google.com/cloudagents/add-google-cloud-ops-agent-repo.sh
        sudo bash add-google-cloud-ops-agent-repo.sh --also-install
        print_success "Google Cloud Ops Agent installed"
    else
        print_warning "Google Cloud Ops Agent already installed"
    fi
    
    # Install logwatch for log monitoring
    sudo apt install -y logwatch
    
    print_success "Monitoring tools installed"
}

# Function to setup logging
setup_logging() {
    print_status "Setting up enhanced logging..."
    
    # Create log directory
    sudo mkdir -p /var/log/security
    
    # Configure rsyslog for security events
    sudo tee -a /etc/rsyslog.conf > /dev/null <<EOF

# Security logging
auth,authpriv.*                    /var/log/security/auth.log
kern.*                            /var/log/security/kern.log
*.emerg                           :omusrmsg:*
EOF
    
    # Restart rsyslog
    sudo systemctl restart rsyslog
    
    print_success "Enhanced logging configured"
}

# Function to create security audit script
create_security_audit() {
    print_status "Creating security audit script..."
    
    sudo tee /usr/local/bin/security-audit.sh > /dev/null <<'EOF'
#!/bin/bash

echo "=== GCP VM Security Audit ==="
echo "Date: $(date)"
echo

echo "=== System Information ==="
echo "Hostname: $(hostname)"
echo "OS: $(lsb_release -d | cut -f2)"
echo "Kernel: $(uname -r)"
echo

echo "=== Open Ports ==="
sudo netstat -tuln | grep LISTEN
echo

echo "=== Active Connections ==="
sudo netstat -tuln | grep ESTABLISHED | head -10
echo

echo "=== Failed Login Attempts ==="
sudo grep "Failed password" /var/log/auth.log | tail -10
echo

echo "=== fail2ban Status ==="
sudo fail2ban-client status
echo

echo "=== System Load ==="
uptime
echo

echo "=== Disk Usage ==="
df -h
echo

echo "=== Memory Usage ==="
free -h
echo

echo "=== Recent Security Events ==="
sudo tail -20 /var/log/security/auth.log 2>/dev/null || echo "No security log found"
echo

echo "=== Cron Jobs ==="
sudo crontab -l 2>/dev/null || echo "No root cron jobs"
echo

echo "=== Active Services ==="
sudo systemctl list-units --type=service --state=active | grep -E "(ssh|fail2ban|ufw|nginx|docker)"
echo

echo "=== Audit Complete ==="
EOF
    
    sudo chmod +x /usr/local/bin/security-audit.sh
    print_success "Security audit script created at /usr/local/bin/security-audit.sh"
}

# Function to setup firewall (UFW)
setup_ufw() {
    print_status "Setting up UFW firewall..."
    
    # Install UFW
    sudo apt install -y ufw
    
    # Reset UFW to default
    sudo ufw --force reset
    
    # Set default policies
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # Allow SSH
    sudo ufw allow ssh
    
    # Allow HTTP/HTTPS
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    
    # Enable UFW
    sudo ufw --force enable
    
    print_success "UFW firewall configured and enabled"
}

# Function to create backup script
create_backup_script() {
    print_status "Creating backup script..."
    
    sudo tee /usr/local/bin/create-backup.sh > /dev/null <<'EOF'
#!/bin/bash

# Create backup of important files
BACKUP_DIR="/var/backups/security-$(date +%Y%m%d)"
sudo mkdir -p $BACKUP_DIR

# Backup SSH config
sudo cp /etc/ssh/sshd_config $BACKUP_DIR/

# Backup fail2ban config
sudo cp /etc/fail2ban/jail.local $BACKUP_DIR/ 2>/dev/null || true

# Backup UFW config
sudo cp /etc/ufw/user.rules $BACKUP_DIR/ 2>/dev/null || true

# Backup system logs
sudo tar -czf $BACKUP_DIR/logs.tar.gz /var/log/auth.log /var/log/syslog 2>/dev/null || true

echo "Backup created at: $BACKUP_DIR"
EOF
    
    sudo chmod +x /usr/local/bin/create-backup.sh
    print_success "Backup script created at /usr/local/bin/create-backup.sh"
}

# Function to display security status
show_security_status() {
    print_status "Security Status Report:"
    echo "================================"
    
    echo "Firewall Rules:"
    gcloud compute firewall-rules list --project=$PROJECT_ID --format="table(name,sourceRanges.list(),allowed[].map().firewall_rule().list())"
    echo
    
    echo "SSH Configuration:"
    echo "Password Authentication: $(sudo grep -i "PasswordAuthentication" /etc/ssh/sshd_config | grep -v "^#" | tail -1)"
    echo "Root Login: $(sudo grep -i "PermitRootLogin" /etc/ssh/sshd_config | grep -v "^#" | tail -1)"
    echo
    
    echo "fail2ban Status:"
    sudo fail2ban-client status 2>/dev/null || echo "fail2ban not running"
    echo
    
    echo "UFW Status:"
    sudo ufw status 2>/dev/null || echo "UFW not configured"
    echo
    
    echo "System Updates:"
    sudo unattended-upgrade --dry-run --debug 2>/dev/null | grep -E "(Checking|Packages" || echo "Auto-updates configured"
    echo
    
    echo "Open Ports:"
    sudo netstat -tuln | grep LISTEN | head -10
    echo
}

# Main execution
main() {
    print_status "Starting GCP VM Security Hardening..."
    
    # Create firewall rules
    create_firewall_rules
    
    # Harden SSH
    harden_ssh
    
    # Setup fail2ban
    setup_fail2ban
    
    # Setup automatic updates
    setup_auto_updates
    
    # Setup monitoring
    setup_monitoring
    
    # Setup logging
    setup_logging
    
    # Setup UFW
    setup_ufw
    
    # Create utility scripts
    create_security_audit
    create_backup_script
    
    # Show final status
    show_security_status
    
    print_success "GCP VM Security Hardening Complete!"
    echo
    print_status "Available commands:"
    echo "  /usr/local/bin/security-audit.sh  - Run security audit"
    echo "  /usr/local/bin/create-backup.sh   - Create security backup"
    echo "  sudo ufw status                    - Check firewall status"
    echo "  sudo fail2ban-client status       - Check fail2ban status"
    echo
    print_warning "IMPORTANT: Test SSH connection before closing this session!"
    print_warning "If you can't connect, you may need to adjust firewall rules."
}

# Run main function
main "$@"
