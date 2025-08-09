#!/bin/bash

# Docker Swarm Initialization Script
# This script initializes a Docker Swarm cluster with proper configuration

set -e  # Exit on any error

echo "=== Docker Swarm Initialization Script ==="

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

# Check if Docker is installed and running
check_docker() {
    print_status "Checking Docker installation..."
    
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker is not running or you don't have permission to access it."
        print_info "Try: sudo systemctl start docker"
        print_info "Or add your user to docker group: sudo usermod -aG docker \$USER"
        exit 1
    fi
    
    print_status "Docker is installed and running."
}

# Check if already in swarm mode
check_swarm_status() {
    print_status "Checking current swarm status..."
    
    if docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        print_warning "This node is already part of a Docker Swarm."
        
        # Show current swarm info
        echo
        print_info "Current Swarm Information:"
        docker node ls 2>/dev/null || print_info "Cannot list nodes (not a manager)"
        echo
        
        read -p "Do you want to leave the current swarm and create a new one? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            print_status "Leaving current swarm..."
            docker swarm leave --force
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
    local listen_addr=""
    
    # Ask user for advertise address
    echo "Docker Swarm needs to know which IP address to advertise to other nodes."
    echo "This should be the IP address that other nodes can reach this manager on."
    echo
    
    read -p "Enter the IP address to advertise (press Enter for auto-detect): " user_ip
    
    if [ -n "$user_ip" ]; then
        advertise_addr="$user_ip"
    else
        # Auto-detect primary IP
        advertise_addr=$(ip route get 8.8.8.8 | awk 'NR==1 {print $7}')
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
    docker swarm init --advertise-addr "$advertise_addr"
    
    if [ $? -eq 0 ]; then
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
    docker node ls
    
    echo
    print_info "Swarm details:"
    docker info --format "{{.Swarm.NodeID}}" | xargs docker node inspect --format "
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
    echo -e "${BLUE}$(docker swarm join-token manager -q | xargs docker swarm join-token manager)${NC}"
    
    echo
    # Get worker join token  
    print_info "To add a worker node to this swarm, run:"
    echo -e "${BLUE}$(docker swarm join-token worker -q | xargs docker swarm join-token worker)${NC}"
    
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
        docker service create \
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
        MANAGER_IP=$(docker info --format '{{.Swarm.NodeAddr}}')
        print_info "http://$MANAGER_IP:8080"
        
        echo
        print_warning "To remove the test service later, run:"
        print_info "docker service rm swarm-test"
    fi
}

# Main function
main() {
    # Perform checks
    check_docker
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
    print_status "Docker Swarm initialization completed successfully! 🐳"
    print_info "Your Docker Swarm cluster is now ready for container orchestration."
}

# Run main function
main