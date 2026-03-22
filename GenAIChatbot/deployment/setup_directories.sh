#!/bin/bash
# Setup directories for chatbot deployment
# This script creates necessary directories and sets proper permissions

set -e

echo "Setting up directories for chatbot deployment..."

# Create application directories
APP_DIR="/opt/chatbot/generative-ai-chatbot"
LOG_DIR="/var/log/chatbot"
DATA_DIR="/var/lib/chatbot/data"
CONFIG_DIR="/etc/chatbot"

# Create directories
echo "Creating directories..."
sudo mkdir -p "$APP_DIR"
sudo mkdir -p "$LOG_DIR"
sudo mkdir -p "$DATA_DIR"
sudo mkdir -p "$CONFIG_DIR"
sudo mkdir -p "/opt/chatbot/venv"

# Create data subdirectories
sudo mkdir -p "$DATA_DIR"

# Set ownership
echo "Setting ownership to chatbot user..."
sudo chown -R chatbot:chatbot "$APP_DIR"
sudo chown -R chatbot:chatbot "$LOG_DIR"
sudo chown -R chatbot:chatbot "$DATA_DIR"
sudo chown -R chatbot:chatbot "$CONFIG_DIR"
sudo chown -R chatbot:chatbot "/opt/chatbot/venv"

# Set permissions
echo "Setting permissions..."
sudo chmod 750 "$APP_DIR"
sudo chmod 750 "$LOG_DIR"
sudo chmod 750 "$DATA_DIR"
sudo chmod 750 "$CONFIG_DIR"
sudo chmod 750 "/opt/chatbot/venv"

# Set permissions for .env file if it exists
if [ -f "$CONFIG_DIR/.env" ]; then
    sudo chmod 600 "$CONFIG_DIR/.env"
    echo "Set permissions for .env file"
fi

echo "Directory setup complete!"
echo "  Application: $APP_DIR"
echo "  Logs: $LOG_DIR"
echo "  Data: $DATA_DIR"
echo "  Config: $CONFIG_DIR"
echo "  Virtual Env: /opt/chatbot/venv"

