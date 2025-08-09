#!/bin/bash

# Complete Docker Installation and Swarm Initialization Script (Non-Interactive)

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }
print_info() { echo -e "${BLUE}[DETAIL]${NC} $1"; }

if [[ $EUID -eq 0 ]]; then
   print_error "Do not run as root. Use a regular user with sudo privileges."
   exit 1
fi

NO_TEST=false
if [[ "$1" == "--no-test" ]]; then
    NO_TEST=true
fi

detect_os() {
    . /etc/os-release
    case "$ID" in
        ubuntu)
            OS="ubuntu"; OS_NAME="Ubuntu"; FALLBACK_PACKAGE="docker.io" ;;
        debian)
            OS="debian"; OS_NAME="Debian"; FALLBACK_PACKAGE="docker.io" ;;
        *)
            print_error "Unsupported OS: $ID"; exit 1 ;;
    esac
    print_status "Detected OS: $OS_NAME"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        return 1
    fi
    if ! docker info &> /dev/null; then
        return 2
    fi
    return 0
}

install_docker_official() {
    print_status "Installing Docker from official repository..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/$OS/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    if [[ "$OS" == "ubuntu" ]]; then
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    else
        echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    fi
    sudo apt-get update -qq
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
}

install_docker_fallback() {
    print_warning "Installing Docker from $OS_NAME repository as fallback..."
    sudo apt-get update -qq
    sudo apt-get install -y -qq $FALLBACK_PACKAGE
}

configure_docker() {
    sudo usermod -aG docker $USER
    sudo systemctl enable --now docker
}

test_docker() {
    sudo docker run --rm hello-world >/dev/null
}

install_docker_if_needed() {
    check_docker
    case $? in
        0) print_status "Docker already installed and running."; return 0 ;;
        2) print_warning "Docker installed but not accessible. Fixing..."
           configure_docker; newgrp docker <<EONG
docker info >/dev/null && echo "Docker fixed."
EONG
           return 0 ;;
        1) print_status "Installing Docker..."
           install_docker_official || install_docker_fallback
           configure_docker
           test_docker || { print_error "Docker test failed!"; exit 1; }
           ;;
    esac
}

check_swarm_status() {
    if sudo docker info --format '{{.Swarm.LocalNodeState}}' | grep -q "active"; then
        print_warning "Already in a swarm. Leaving..."
        sudo docker swarm leave --force
    fi
}

get_advertise_ip() {
    ip route get 8.8.8.8 | awk 'NR==1 {print $7}' 2>/dev/null || \
    ip -4 addr show | grep -E "inet.*scope global" | awk 'NR==1 {print $2}' | cut -d'/' -f1
}

initialize_swarm() {
    local advertise_addr
    advertise_addr=$(get_advertise_ip)
    if [ -z "$advertise_addr" ]; then
        print_error "No valid IP found for Swarm."
        exit 1
    fi
    print_status "Initializing Swarm with IP: $advertise_addr"
    sudo docker swarm init --advertise-addr "$advertise_addr"
}

show_swarm_info() {
    print_info "Node list:"
    sudo docker node ls
    echo
    print_info "Manager join token:"
    sudo docker swarm join-token manager
    echo
    print_info "Worker join token:"
    sudo docker swarm join-token worker
}

create_test_service() {
    if [ "$NO_TEST" = true ]; then
        print_status "Skipping test service creation."
        return
    fi
    print_status "Creating test nginx service..."
    sudo docker service create \
        --name swarm-test \
        --replicas 2 \
        --publish 8080:80 \
        nginx:alpine
    print_info "Test service running at: http://$(get_advertise_ip):8080"
}

main() {
    detect_os
    install_docker_if_needed
    check_swarm_status
    initialize_swarm
    show_swarm_info
    create_test_service
    print_status "Setup complete! 🐳"
}

main "$@"
