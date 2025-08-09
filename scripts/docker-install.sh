#!/bin/bash

# Complete Docker Installation and Swarm Initialization Script
# This script installs Docker and initializes a Docker Swarm cluster

set -e  # Exit on any error

echo "=== Complete Docker Installation and Swarm Setup ==="
echo "This script will install Docker and initialize Docker Swarm"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[DETAIL]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root. Please run as a regular user with sudo privileges."
   exit 1
fi

# Detect OS
detect_os() {
    print_status "Detecting operating system..."
    if grep -q "Ubuntu" /etc/os-release; then
        OS="ubuntu"
        OS_NAME="Ubuntu"
        FALLBACK_PACKAGE="docker.io"
    elif grep -q "Debian" /etc/os-release; then
        OS="debian" 
        OS_NAME="Debian"
        FALLBACK_PACKAGE="docker.io"
    else
        print_error "This script only supports Ubuntu and Debian"
        exit 1
    fi
    
    print_status "Detected OS: $OS_NAME"
}

# Check if Docker is installed and running
check_docker() {
    print_status "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        return 1  # Docker not installed
    fi
    
    if ! docker info &> /dev/null; then
        print_warning "Docker is installed but not accessible."
        print_info "Try: sudo systemctl start docker"
        print_info "Or add your user to docker group: sudo usermod -aG docker \$USER"
        return 2  # Docker installed but not accessible
    fi
    
    print_status "Docker is installed and running."
    return 0  # Docker working fine
}

# Function to install Docker from official repository
install_docker_official() {
    print_status "Installing Docker from official Docker repository for $OS_NAME..."
    
    # Update package index
    print_status "Updating package index..."
    sudo apt-get update
    
    # Install prerequisites
    print_status "Installing prerequisites..."
    sudo apt-get install -y ca-certificates curl
    
    # Create keyring directory
    print_status "Setting up Docker GPG key..."
    sudo install -m 0755 -d /etc/apt/keyrings
    
    # Download Docker's official GPG key (OS-specific URL)
    sudo curl -fsSL https://download.docker.com/linux/$OS/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    
    # Add Docker repository to Apt sources (OS-specific)
    print_status "Adding Docker repository..."
    if [[ "$OS" == "ubuntu" ]]; then
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
          $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    else  # Debian
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
          $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi
    
    # Update package index again
    sudo apt-get update
    
    # Install Docker packages
    print_status "Installing Docker CE packages..."
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    return 0
}

# Function to install Docker from distribution repository (fallback)
install_docker_fallback() {
    print_warning "Installing Docker from $OS_NAME repository as fallback..."
    sudo apt-get update
    sudo apt-get install -y $FALLBACK_PACKAGE
    return 0
}

# Function to configure Docker
configure_docker() {
    print_status "Configuring Docker..."
    
    # Add current user to docker group
    print_status "Adding user to docker group..."
    sudo usermod -aG docker $USER
    
    # Start and enable Docker service
    print_status "Starting Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker
    
    print_status "Docker service status:"
    sudo systemctl status docker --no-pager -l
}

# Function to test Docker installation
test_docker() {
    print_status "Testing Docker installation..."
    
    # Test with sudo first
    if sudo docker run hello-world; then
        print_status "Docker test successful!"
        return 0
    else
        print_error "Docker test failed!"
        return 1
    fi
}

# Install Docker if needed
install_docker_if_needed() {
    local docker_status
    check_docker
    docker_status=$?
    
    if [ $docker_status -eq 0 ]; then
        print_status "Docker is already installed and working."
        return 0
    elif [ $docker_status -eq 2 ]; then
        print_warning "Docker is installed but not accessible. Configuring..."
        configure_docker
        
        # Refresh group membership for current session
        newgrp docker <<EONG
if docker info &> /dev/null; then
    echo "Docker is now accessible!"
else
    echo "Please log out and log back in, then re-run this script."
    exit 1
fi
EONG
        return 0
    else
        # Docker not installed - install it
        print_status "Installing Docker..."
        
        # Try official installation first
        if install_docker_official; then
            print_status "Official Docker installation completed successfully!"
        else
            print_error "Official installation failed. Trying fallback method..."
            if install_docker_fallback; then
                print_status "Fallback installation completed successfully!"
            else
                print_error "Both installation methods failed!"
                exit 1
            fi
        fi
        
        # Configure Docker
        configure_docker
        
        # Test installation
        if test_docker; then
            print_status "Docker installation completed successfully!"
        else
            print_error "Docker installation failed testing!"
            exit 1
        fi
        
        # Refresh group membership for swarm initialization
        print_warning "Refreshing group membership for Docker access..."
        newgrp docker <<EONG
exit 0
EONG
    fi
}

# Check if already in swarm mode
check_swarm_status() {
    print_status "Checking current swarm status..."
    
    if sudo docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        print_warning "This node is already part of a Docker Swarm."
        
        # Show current swarm info
        echo
        print_info "Current Swarm Information:"
        sudo docker node ls 2>/dev/null || print_info "Cannot list nodes (not a manager)"
        echo
        
        read -p "Do you want to leave the current swarm and create a new one? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Leaving current swarm..."
            sudo docker swarm leave --force
        else
            print_status "Keeping current swarm configuration."
            show_swarm_info
            exit 0
        fi
    fi
}

# Get network interfaces and IP addresses
get_network_info() {
    print_status "Detecting network interfaces..."
    
    # Get all non-loopback IP addresses
    INTERFACES=$(ip -4 addr show | grep -E "inet.*scope global" | awk '{print $2}' | cut -d'/' -f1)
    
    if [ -z "$INTERFACES" ]; then
        print_error "No network interfaces found!"
        exit 1
    fi
    
    echo
    print_info "Available IP addresses:"
    i=1
    for ip in $INTERFACES; do
        echo "  $i) $ip"
        ((i++))
    done
    echo
}

# Function to initialize Docker Swarm
initialize_swarm() {
    local advertise_addr=""
    
    # Ask user for advertise address
    echo "Docker Swarm needs to know which IP address to advertise to other nodes."
    echo "This should be the IP address that other nodes can reach this manager on."
    echo
    
    read -p "Enter the IP address to advertise (press Enter for auto-detect): " user_ip
    
    if [ -n "$user_ip" ]; then
        advertise_addr="$user_ip"
    else
        # Auto-detect primary IP
        advertise_addr=$(ip route get 8.8.8.8 | awk 'NR==1 {print $7}' 2>/dev/null)
        if [ -z "$advertise_addr" ]; then
            # Fallback to first non-loopback interface
            advertise_addr=$(ip -4 addr show | grep -E "inet.*scope global" | awk 'NR==1 {print $2}' | cut -d'/' -f1)
        fi
    fi
    
    if [ -z "$advertise_addr" ]; then
        print_error "Could not determine IP address for swarm initialization."
        exit 1
    fi
    
    print_status "Using advertise address: $advertise_addr"
    
    # Initialize the swarm
    print_status "Initializing Docker Swarm..."
    
    # Use sudo initially, then provide instructions for non-sudo access
    if sudo docker swarm init --advertise-addr "$advertise_addr"; then
        print_status "Docker Swarm initialized successfully!"
    else
        print_error "Failed to initialize Docker Swarm."
        exit 1
    fi
}

# Function to show swarm information and join commands
show_swarm_info() {
    echo
    print_status "=== Swarm Information ==="
    
    # Show node information
    print_info "Current node status:"
    sudo docker node ls
    
    echo
    print_info "Swarm details:"
    NODE_ID=$(sudo docker info --format "{{.Swarm.NodeID}}")
    sudo docker node inspect "$NODE_ID" --format "
Manager: {{.Spec.Role}}
Node ID: {{.ID}}
Hostname: {{.Description.Hostname}}
IP Address: {{.Status.Addr}}
State: {{.Status.State}}
Availability: {{.Spec.Availability}}"
    
    echo
    print_status "=== Join Commands ==="
    
    # Get manager join token
    print_info "To add a manager node to this swarm, run:"
    echo -e "${BLUE}$(sudo docker swarm join-token manager)${NC}"
    
    echo
    # Get worker join token  
    print_info "To add a worker node to this swarm, run:"
    echo -e "${BLUE}$(sudo docker swarm join-token worker)${NC}"
    
    echo
    print_status "=== Useful Swarm Commands ==="
    echo "• List nodes: docker node ls"
    echo "• Leave swarm: docker swarm leave --force"
    echo "• Create service: docker service create --name <service_name> <image>"
    echo "• List services: docker service ls"
    echo "• Scale service: docker service scale <service_name>=<replicas>"
    echo "• Remove service: docker service rm <service_name>"
}

# Function to create a simple test service
create_test_service() {
    echo
    read -p "Would you like to create a test service to verify swarm functionality? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        print_status "Creating test web service..."
        
        # Create a simple nginx service
        sudo docker service create \
            --name swarm-test \
            --replicas 2 \
            --publish 8080:80 \
            nginx:alpine
        
        echo
        print_status "Test service created! Check status with:"
        print_info "docker service ls"
        print_info "docker service ps swarm-test"
        
        echo
        print_status "The test service should be accessible at:"
        MANAGER_IP=$(sudo docker info --format '{{.Swarm.NodeAddr}}')
        print_info "http://$MANAGER_IP:8080"
        
        echo
        print_warning "To remove the test service later, run:"
        print_info "docker service rm swarm-test"
    fi
}

# Main function
main() {
    # Detect operating system
    detect_os
    
    echo
    print_status "=== Phase 1: Docker Installation ==="
    
    # Install Docker if needed
    install_docker_if_needed
    
    echo
    print_status "=== Phase 2: Docker Swarm Initialization ==="
    
    # Check swarm status
    check_swarm_status
    
    # Show network information
    get_network_info
    
    # Initialize swarm
    initialize_swarm
    
    # Show swarm information
    show_swarm_info
    
    # Optionally create test service
    create_test_service
    
    echo
    print_status "=== Setup Complete! ==="
    print_status "✓ Docker installed and configured"
    print_status "✓ Docker Swarm initialized"
    print_status "✓ Ready for container orchestration"
    
    echo
    print_warning "IMPORTANT NOTES:"
    print_warning "• Log out and log back in to use Docker without sudo"
    print_warning "• Or run 'newgrp docker' to refresh group membership"
    print_warning "• Save the join tokens above to add other nodes to your swarm"
    
    echo
    print_status "Setup completed successfully! 🐳"
}

# Run main function
main