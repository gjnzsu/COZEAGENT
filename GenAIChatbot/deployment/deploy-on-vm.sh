#!/bin/bash
# Manual deployment script to run ON the VM
# Use this if file transfer from local machine fails
# 
# Prerequisites:
#   1. Files must already be on the VM at ~/GenAIChatbot
#   2. Or you can clone from git, or transfer via other means
#
# Usage on VM:
#   cd ~/GenAIChatbot/deployment
#   sudo bash deploy-on-vm.sh

set -e

echo "=========================================="
echo "Chatbot Deployment - On VM"
echo "=========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Check if files exist
if [ ! -d ~/GenAIChatbot/deployment ]; then
    echo "ERROR: ~/GenAIChatbot/deployment directory not found"
    echo ""
    echo "Please ensure files are on the VM. Options:"
    echo "  1. Transfer files manually using gcloud compute scp"
    echo "  2. Clone from git repository"
    echo "  3. Upload via Cloud Storage"
    echo ""
    echo "Current directory: $(pwd)"
    echo "Home directory: $HOME"
    echo "Listing home:"
    ls -la ~/ | head -10
    exit 1
fi

SCRIPT_DIR=~/GenAIChatbot/deployment
APP_DIR=/opt/chatbot/generative-ai-chatbot

echo ""
echo "Step 1: Running installation..."
cd "$SCRIPT_DIR"
if [ -f install.sh ]; then
    bash install.sh
else
    echo "ERROR: install.sh not found"
    exit 1
fi

echo ""
echo "Step 2: Checking configuration..."
if [ ! -f /etc/chatbot/.env ]; then
    echo "WARNING: /etc/chatbot/.env not found"
    echo "Creating from template..."
    if [ -f "$SCRIPT_DIR/env.template" ]; then
        cp "$SCRIPT_DIR/env.template" /etc/chatbot/.env
        chmod 600 /etc/chatbot/.env
        chown chatbot:chatbot /etc/chatbot/.env
        echo "Created /etc/chatbot/.env from template"
        echo "Please edit it with: sudo nano /etc/chatbot/.env"
    else
        echo "ERROR: env.template not found"
        exit 1
    fi
else
    echo "Configuration file exists"
fi

echo ""
echo "Step 3: Deploying application..."
cd "$SCRIPT_DIR"
if [ -f deploy.sh ]; then
    bash deploy.sh
else
    echo "ERROR: deploy.sh not found"
    exit 1
fi

echo ""
echo "Step 4: Verifying deployment..."
if [ -f post_install.sh ]; then
    bash post_install.sh
else
    echo "Running basic verification..."
    systemctl status chatbot.service --no-pager -l | head -20
fi

echo ""
echo "=========================================="
echo "Deployment complete!"
echo "=========================================="

