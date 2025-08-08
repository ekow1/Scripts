#!/bin/bash

# Simple Docker installation with Swarm setup

echo "Installing Docker..."

# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh

# Start Docker service
sudo systemctl start docker
sudo systemctl enable docker

# Add current user to docker group
sudo usermod -aG docker $USER

echo "Docker installed successfully!"

# Initialize Docker Swarm
echo "Setting up Docker Swarm..."
sudo docker swarm init

# Show swarm status
echo "Swarm Status:"
sudo docker node ls

echo ""
echo "Installation complete!"
echo "To join other nodes to this swarm, use:"
echo "docker swarm join-token worker"
echo ""
echo "Note: You may need to logout and login again to use docker without sudo"