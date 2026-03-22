#!/bin/bash
# Deployment script for chatbot application
# This script copies application files and starts the service

set -e

echo "=========================================="
echo "Chatbot Deployment - Application Deploy"
echo "=========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="/opt/chatbot/generative-ai-chatbot"
SOURCE_DIR="$(dirname "$SCRIPT_DIR")/generative-ai-chatbot"

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory not found: $SOURCE_DIR"
    echo "Please ensure the generative-ai-chatbot directory is in the parent directory of deployment/"
    exit 1
fi

# Copy application files
echo ""
echo "Step 1: Copying application files..."
echo "  From: $SOURCE_DIR"
echo "  To: $APP_DIR"

# Create destination directory if it doesn't exist
mkdir -p "$APP_DIR"

# Check if rsync is available, otherwise use cp
if command -v rsync &> /dev/null; then
    echo "  Using rsync for file transfer..."
    # Copy files (excluding unnecessary files)
    rsync -av --progress \
        --exclude='__pycache__' \
        --exclude='*.pyc' \
        --exclude='.git' \
        --exclude='.env' \
        --exclude='*.log' \
        --exclude='data/*.db' \
        --exclude='data/*.db-journal' \
        --exclude='data/*.db-wal' \
        --exclude='data/*.db-shm' \
        --exclude='node_modules' \
        --exclude='.pytest_cache' \
        --exclude='*.egg-info' \
        "$SOURCE_DIR/" "$APP_DIR/"
else
    echo "  rsync not available, using cp (this may take longer)..."
    # Remove destination if it exists to ensure clean copy
    if [ -d "$APP_DIR" ] && [ "$(ls -A $APP_DIR 2>/dev/null)" ]; then
        rm -rf "$APP_DIR"/*
    fi
    
    # Copy all files first
    echo "  Copying files..."
    cp -r "$SOURCE_DIR"/* "$APP_DIR/" 2>/dev/null || true
    
    # Copy hidden files (but exclude .git and .env)
    if [ -d "$SOURCE_DIR/.git" ]; then
        # Skip .git directory
        find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -name '.*' ! -name '.git' ! -name '.env' -exec cp -r {} "$APP_DIR/" \; 2>/dev/null || true
    else
        find "$SOURCE_DIR" -mindepth 1 -maxdepth 1 -name '.*' ! -name '.env' -exec cp -r {} "$APP_DIR/" \; 2>/dev/null || true
    fi
    
    # Clean up excluded files/directories
    echo "  Cleaning up excluded files..."
    find "$APP_DIR" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
    find "$APP_DIR" -type f -name '*.pyc' -delete 2>/dev/null || true
    find "$APP_DIR" -type d -name '.git' -exec rm -rf {} + 2>/dev/null || true
    find "$APP_DIR" -type f -name '.env' -delete 2>/dev/null || true
    find "$APP_DIR" -type f -name '*.log' -delete 2>/dev/null || true
    find "$APP_DIR" -type d -name 'node_modules' -exec rm -rf {} + 2>/dev/null || true
    find "$APP_DIR" -type d -name '.pytest_cache' -exec rm -rf {} + 2>/dev/null || true
    find "$APP_DIR" -type d -name '*.egg-info' -exec rm -rf {} + 2>/dev/null || true
    find "$APP_DIR" -type f -name '*.db' -path '*/data/*' -delete 2>/dev/null || true
    find "$APP_DIR" -type f -name '*.db-journal' -delete 2>/dev/null || true
    find "$APP_DIR" -type f -name '*.db-wal' -delete 2>/dev/null || true
    find "$APP_DIR" -type f -name '*.db-shm' -delete 2>/dev/null || true
fi

# Copy run_production.py if it exists in deployment directory
if [ -f "$SCRIPT_DIR/run_production.py" ]; then
    cp "$SCRIPT_DIR/run_production.py" "$APP_DIR/run_production.py"
    chmod +x "$APP_DIR/run_production.py"
    echo "  Copied run_production.py"
fi

# Set ownership
echo ""
echo "Step 2: Setting file ownership..."
chown -R chatbot:chatbot "$APP_DIR"

# Fix file permissions (ensure nginx can read static files)
echo ""
echo "Step 2.5: Fixing file permissions for nginx access..."
# Set directory permissions to 755 (rwxr-xr-x) - allows traversal
find "$APP_DIR" -type d -exec chmod 755 {} \;
# Set file permissions to 644 (rw-r--r--) - allows reading
find "$APP_DIR" -type f -exec chmod 644 {} \;
# Make scripts executable
find "$APP_DIR" -name "*.sh" -exec chmod 755 {} \;
find "$APP_DIR" -name "*.py" -exec chmod 755 {} \;
echo "  ✓ Permissions fixed (directories: 755, files: 644, scripts: 755)"

# Setup directories
echo ""
echo "Step 3: Setting up data directories..."
bash "$SCRIPT_DIR/setup_directories.sh"

# Install/update Python dependencies in virtual environment
echo ""
echo "Step 4: Installing Python dependencies..."
VENV_DIR="/opt/chatbot/venv"

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    echo "  Creating Python virtual environment..."
    python3 -m venv "$VENV_DIR"
    chown -R chatbot:chatbot "$VENV_DIR"
fi

# Check if requirements-poc.txt exists (preferred for PoC)
REQUIREMENTS_FILE="$APP_DIR/requirements.txt"
if [ -f "$APP_DIR/requirements-poc.txt" ]; then
    REQUIREMENTS_FILE="$APP_DIR/requirements-poc.txt"
    echo "  Using minimal PoC requirements (requirements-poc.txt)"
elif [ -f "$APP_DIR/requirements.txt" ]; then
    REQUIREMENTS_FILE="$APP_DIR/requirements.txt"
    echo "  Using full requirements (requirements.txt)"
fi

# Install dependencies
if [ -f "$REQUIREMENTS_FILE" ]; then
    echo "  Installing from $REQUIREMENTS_FILE in virtual environment..."
    "$VENV_DIR/bin/pip" install --upgrade pip --quiet
    "$VENV_DIR/bin/pip" install -r "$REQUIREMENTS_FILE"
    if [ $? -eq 0 ]; then
        echo "  ✓ Dependencies installed successfully"
    else
        echo "  ✗ Error installing dependencies"
        exit 1
    fi
else
    echo "  ⚠ Warning: requirements file not found"
    echo "  Installing essential packages manually..."
    "$VENV_DIR/bin/pip" install --upgrade pip --quiet
    "$VENV_DIR/bin/pip" install Flask flask-cors PyJWT bcrypt openai google-generativeai python-dotenv requests jira PyPDF2 langchain langchain-core langchain-openai langgraph mcp cozepy flasgger protobuf
fi

# Verify Flask is installed
echo "  Verifying Flask installation..."
if "$VENV_DIR/bin/python3" -c "import flask; print(f'Flask {flask.__version__}')" 2>/dev/null; then
    echo "  ✓ Flask is installed"
else
    echo "  ✗ Flask installation verification failed"
    echo "  Installing Flask manually..."
    "$VENV_DIR/bin/pip" install Flask flask-cors
fi

# Make run_production.py executable
if [ -f "$APP_DIR/run_production.py" ]; then
    chmod +x "$APP_DIR/run_production.py"
fi

# Check if .env file exists
echo ""
echo "Step 5: Checking configuration..."
if [ ! -f /etc/chatbot/.env ]; then
    echo "  ⚠ Warning: /etc/chatbot/.env not found"
    echo "  Please create it from .env.template and configure your settings"
    echo "  Then run: sudo systemctl start chatbot"
else
    echo "  Configuration file found"
fi

# Reload systemd and start service
echo ""
echo "Step 6: Starting chatbot service..."
systemctl daemon-reload
systemctl enable chatbot.service
systemctl restart chatbot.service

# Wait a moment for service to start
sleep 2

# Check service status
if systemctl is-active --quiet chatbot.service; then
    echo "  ✓ Chatbot service is running"
else
    echo "  ⚠ Warning: Chatbot service is not running"
    echo "  Check status with: sudo systemctl status chatbot"
    echo "  Check logs with: sudo journalctl -u chatbot -n 50"
fi

# Reload Nginx
echo ""
echo "Step 7: Reloading Nginx..."
if systemctl is-active --quiet nginx; then
    systemctl reload nginx
    echo "  ✓ Nginx reloaded"
else
    echo "  Starting Nginx..."
    systemctl start nginx
    systemctl enable nginx
fi

echo ""
echo "=========================================="
echo "Deployment complete!"
echo "=========================================="
echo ""
echo "Service status:"
systemctl status chatbot.service --no-pager -l || true
echo ""
echo "Next steps:"
echo "1. Verify deployment: sudo bash $SCRIPT_DIR/post_install.sh"
echo "2. Check logs: sudo journalctl -u chatbot -f"
echo "3. Access the application at http://your-server-ip"
echo ""

