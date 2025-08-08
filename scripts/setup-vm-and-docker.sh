#!/bin/bash

# Exit on error
set -e

echo "🔑 Updating system packages..."
sudo apt update && sudo apt upgrade -y

echo "🐳 Installing Docker..."
# Install Docker prerequisites
sudo apt install -y ca-certificates curl gnupg lsb-release

# Add Docker GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update and install Docker
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "✅ Docker installed successfully."

echo "👤 Adding current user to docker group..."
sudo usermod -aG docker $USER
echo "⚠️ You may need to log out and back in for group changes to take effect."

# Enable Docker on startup
sudo systemctl enable docker
sudo systemctl start docker

echo "🔧 Initializing Docker Swarm..."

# Check if already part of a swarm
if docker info | grep -q "Swarm: active"; then
  echo "🚨 Swarm already initialized."
else
  # Initialize swarm on default interface
  docker swarm init
  echo "✅ Docker Swarm initialized."
fi

echo "🎉 Docker & Swarm setup complete!"
