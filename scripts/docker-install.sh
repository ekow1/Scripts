#!/bin/sh
# GCP-friendly Docker installation + Swarm initialization script

set -eu

GREEN="[INFO]"
YELLOW="[WARN]"
RED="[ERR]"

log() { printf "%s %s\n" "$1" "$2"; }
die() { log "$RED" "$1"; exit 1; }

if [ "$(id -u)" -eq 0 ]; then
    die "Do not run as root. Use a regular user with sudo privileges."
fi

detect_os() {
    if [ -r /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            ubuntu) OS="ubuntu"; OS_NAME="Ubuntu"; FALLBACK_PACKAGE="docker.io" ;;
            debian) OS="debian"; OS_NAME="Debian"; FALLBACK_PACKAGE="docker.io" ;;
            *) die "Unsupported OS: $ID" ;;
        esac
    else
        die "Cannot detect OS type."
    fi
    log "$GREEN" "Detected OS: $OS_NAME"
}

check_docker() {
    if command -v docker >/dev/null 2>&1; then
        if docker info >/dev/null 2>&1; then
            return 0
        else
            return 2
        fi
    fi
    return 1
}

install_docker_official() {
    log "$GREEN" "Installing Docker from official repository..."
    sudo apt-get update -qq || die "Failed to update package lists."
    sudo apt-get install -y -qq ca-certificates curl gnupg lsb-release || die "Failed to install dependencies."
    sudo install -m 0755 -d /etc/apt/keyrings
    curl -fsSL "https://download.docker.com/linux/$OS/gpg" | sudo tee /etc/apt/keyrings/docker.asc >/dev/null || die "Failed to fetch GPG key."
    sudo chmod a+r /etc/apt/keyrings/docker.asc
    CODENAME=$(grep VERSION_CODENAME /etc/os-release | cut -d= -f2)
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/$OS $CODENAME stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
    sudo apt-get update -qq || die "Failed to update Docker repo."
    sudo apt-get install -y -qq docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin || die "Failed to install Docker."
}

install_docker_fallback() {
    log "$YELLOW" "Official repo failed, installing $FALLBACK_PACKAGE..."
    sudo apt-get update -qq || die "Failed to update package lists."
    sudo apt-get install -y -qq "$FALLBACK_PACKAGE" || die "Failed to install fallback package."
}

configure_docker() {
    sudo usermod -aG docker "$USER"
    sudo systemctl enable --now docker || die "Failed to start Docker."
}

test_docker() {
    log "$GREEN" "Testing Docker installation..."
    if ! sudo docker run --rm hello-world >/dev/null 2>&1; then
        die "Docker test run failed."
    fi
}

init_swarm() {
    log "$GREEN" "Initializing Docker Swarm..."
    if ! docker info 2>/dev/null | grep -q "Swarm: active"; then
        sudo docker swarm init --advertise-addr "$(hostname -I | awk '{print $1}')" || \
            die "Swarm initialization failed."
        log "$GREEN" "Docker Swarm initialized successfully."
    else
        log "$YELLOW" "Swarm already active. Skipping initialization."
    fi
}

install_docker_if_needed() {
    check_docker
    case $? in
        0) log "$GREEN" "Docker already installed and running." ;;
        2) log "$YELLOW" "Docker installed but not accessible. Fixing..."; configure_docker ;;
        1) install_docker_official || install_docker_fallback; configure_docker; test_docker ;;
    esac
}

main() {
    log "$GREEN" "=== Docker + Swarm Setup Script (GCP Friendly) ==="
    detect_os
    install_docker_if_needed
    init_swarm
    log "$GREEN" "Setup complete!"
}

main "$@"
