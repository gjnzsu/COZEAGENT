#!/bin/bash
# Install Node.js 18+ LTS for MCP server support
# This script installs Node.js via NodeSource repository

set -e

echo "Installing Node.js for MCP server support..."

# Check if Node.js is already installed
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    echo "Node.js is already installed: $NODE_VERSION"
    
    # Check if version is 18 or higher
    MAJOR_VERSION=$(echo "$NODE_VERSION" | sed 's/v\([0-9]*\).*/\1/')
    if [ "$MAJOR_VERSION" -ge 18 ]; then
        echo "Node.js version is sufficient (>= 18)"
        exit 0
    else
        echo "Node.js version is too old, will upgrade..."
    fi
fi

# Update package list
echo "Updating package list..."
sudo apt-get update

# Install prerequisites
echo "Installing prerequisites..."
sudo apt-get install -y curl gnupg2

# Add NodeSource repository for Node.js 18 LTS
echo "Adding NodeSource repository..."
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -

# Install Node.js
echo "Installing Node.js..."
sudo apt-get install -y nodejs

# Verify installation
echo "Verifying installation..."
NODE_VERSION=$(node --version)
NPM_VERSION=$(npm --version)
NPX_VERSION=$(npx --version || echo "npx available")

echo "✓ Node.js installed: $NODE_VERSION"
echo "✓ npm installed: $NPM_VERSION"
echo "✓ npx: $NPX_VERSION"

# Verify npx is working
if command -v npx &> /dev/null; then
    echo "✓ npx is available for MCP server support"
else
    echo "⚠ Warning: npx not found, but npm is installed"
fi

echo "Node.js setup complete!"

