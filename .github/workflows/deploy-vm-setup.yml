name: Setup VM and Docker

on:
  push:
    branches: [ main ]

jobs:
  setup:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
        
    - name: Copy setup script to server
      uses: appleboy/scp-action@v0.1.4
      with:
        host: ${{ secrets.PRODUCTION_VM_IP }}
        username: ${{ secrets.PRODUCTION_SSH_USER }}
        key: ${{ secrets.VM_SSH_PRIVATE_KEY }}
        passphrase: ${{ secrets.VM_SSH_PRIVATE_KEY_PASSPHRASE }}
        source: "setup-vm-and-docker.sh"
        target: "/tmp/"
        
    - name: Run setup script
      uses: appleboy/ssh-action@v1.0.0
      with:
        host: ${{ secrets.PRODUCTION_VM_IP }}
        username: ${{ secrets.PRODUCTION_SSH_USER }}
        key: ${{ secrets.VM_SSH_PRIVATE_KEY }}
        passphrase: ${{ secrets.VM_SSH_PRIVATE_KEY_PASSPHRASE }}
        script: |
          # Make script executable and run it
          chmod +x /tmp/setup-vm-and-docker.sh
          /tmp/setup-vm-and-docker.sh
          
          # Show final status
          echo "=== Setup Complete ==="
          docker --version
          docker node ls
          docker stack ls