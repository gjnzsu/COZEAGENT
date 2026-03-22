#!/bin/bash
# Main installation script for chatbot deployment
# This script sets up the system environment for the chatbot service

set -e

echo "=========================================="
echo "Chatbot Deployment - System Installation"
echo "=========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Update system packages
echo ""
echo "Step 1: Updating system packages..."
apt-get update
apt-get upgrade -y

# Install Python 3.10+ and pip
echo ""
echo "Step 2: Installing Python and pip..."
apt-get install -y python3 python3-pip python3-venv

# Verify Python version
PYTHON_VERSION=$(python3 --version | cut -d' ' -f2 | cut -d'.' -f1,2)
echo "Python version: $(python3 --version)"

# Install Node.js (for MCP servers)
echo ""
echo "Step 3: Installing Node.js..."
if [ -f "$(dirname "$0")/setup-nodejs.sh" ]; then
    bash "$(dirname "$0")/setup-nodejs.sh"
else
    echo "setup-nodejs.sh not found, installing Node.js directly..."
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash -
    apt-get install -y nodejs
fi

# Install Nginx and rsync (for faster file transfers)
echo ""
echo "Step 4: Installing Nginx and rsync..."
apt-get install -y nginx rsync

# Create chatbot user and group
echo ""
echo "Step 5: Creating chatbot user..."
if id "chatbot" &>/dev/null; then
    echo "User 'chatbot' already exists"
else
    useradd -r -s /bin/bash -d /opt/chatbot -m chatbot
    echo "User 'chatbot' created"
fi

# Create directory structure
echo ""
echo "Step 6: Creating directory structure..."
bash "$(dirname "$0")/setup_directories.sh"

# Install Python and create virtual environment
echo ""
echo "Step 7: Setting up Python virtual environment..."
apt-get install -y python3-venv python3-full

# Create virtual environment for chatbot
VENV_DIR="/opt/chatbot/venv"

# Ensure parent directory exists
mkdir -p /opt/chatbot

# Remove existing venv if it's incomplete
if [ -d "$VENV_DIR" ] && [ ! -f "$VENV_DIR/bin/pip" ]; then
    echo "Removing incomplete virtual environment..."
    rm -rf "$VENV_DIR"
fi

# Create virtual environment
if [ ! -d "$VENV_DIR" ]; then
    echo "Creating virtual environment at $VENV_DIR..."
    python3 -m venv "$VENV_DIR"
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to create virtual environment"
        exit 1
    fi
    echo "Virtual environment created successfully"
else
    echo "Virtual environment already exists"
fi

# Verify venv was created correctly
if [ ! -f "$VENV_DIR/bin/pip" ]; then
    echo "ERROR: Virtual environment is incomplete (pip not found)"
    echo "Removing and recreating..."
    rm -rf "$VENV_DIR"
    python3 -m venv "$VENV_DIR"
    if [ $? -ne 0 ] || [ ! -f "$VENV_DIR/bin/pip" ]; then
        echo "ERROR: Failed to create virtual environment. Please check Python installation."
        exit 1
    fi
fi

# Set ownership
chown -R chatbot:chatbot "$VENV_DIR"
chmod -R 755 "$VENV_DIR"

# Install Python dependencies in virtual environment
echo ""
echo "Step 8: Installing Python dependencies..."
if [ -f "/opt/chatbot/generative-ai-chatbot/requirements.txt" ]; then
    echo "Installing from requirements.txt in virtual environment..."
    "$VENV_DIR/bin/pip" install --upgrade pip
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to upgrade pip"
        exit 1
    fi
    "$VENV_DIR/bin/pip" install -r /opt/chatbot/generative-ai-chatbot/requirements.txt
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to install dependencies"
        exit 1
    fi
    echo "✓ Dependencies installed successfully"
else
    echo "⚠ Warning: requirements.txt not found. Will install during deploy.sh"
fi

# Copy systemd service file
echo ""
echo "Step 8: Setting up systemd service..."
if [ -f "$(dirname "$0")/chatbot.service" ]; then
    cp "$(dirname "$0")/chatbot.service" /etc/systemd/system/chatbot.service
    systemctl daemon-reload
    echo "Systemd service file installed"
else
    echo "⚠ Warning: chatbot.service not found"
fi

# Setup Nginx configuration
echo ""
echo "Step 9: Setting up Nginx configuration..."
if [ -f "$(dirname "$0")/nginx.conf" ]; then
    cp "$(dirname "$0")/nginx.conf" /etc/nginx/sites-available/chatbot
    
    # Create symlink if it doesn't exist
    if [ ! -L /etc/nginx/sites-enabled/chatbot ]; then
        ln -s /etc/nginx/sites-available/chatbot /etc/nginx/sites-enabled/chatbot
    fi
    
    # Test Nginx configuration
    if nginx -t; then
        echo "Nginx configuration is valid"
    else
        echo "⚠ Warning: Nginx configuration test failed"
    fi
else
    echo "⚠ Warning: nginx.conf not found"
fi

# Setup environment file template
echo ""
echo "Step 9: Setting up environment file template..."
if [ -f "$(dirname "$0")/env.template" ]; then
    if [ ! -f /etc/chatbot/.env ]; then
        cp "$(dirname "$0")/env.template" /etc/chatbot/.env
        chmod 600 /etc/chatbot/.env
        chown chatbot:chatbot /etc/chatbot/.env
        echo "Environment file template copied to /etc/chatbot/.env"
        echo "⚠ IMPORTANT: Edit /etc/chatbot/.env and set your actual configuration values!"
    else
        echo "Environment file already exists at /etc/chatbot/.env"
    fi
else
    echo "⚠ Warning: .env.template not found"
fi

echo ""
echo "=========================================="
echo "Installation complete!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. Edit /etc/chatbot/.env and configure your API keys and settings"
echo "2. Run deploy.sh to copy application files and start the service"
echo "3. Run post_install.sh to verify the deployment"
echo ""

