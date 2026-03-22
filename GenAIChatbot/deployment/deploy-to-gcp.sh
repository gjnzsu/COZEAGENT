#!/bin/bash
# Deploy chatbot to Google Cloud VM
# 
# Usage:
#   ./deploy-to-gcp.sh <vm-name> [zone] [project-id]
#   ./deploy-to-gcp.sh chatbot-vm us-central1-a my-project-id
#
# Or set environment variables:
#   export VM_NAME=chatbot-vm
#   export VM_ZONE=us-central1-a
#   export PROJECT_ID=my-project-id
#   ./deploy-to-gcp.sh

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored messages
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get parameters
VM_NAME=${1:-${VM_NAME}}
VM_ZONE=${2:-${VM_ZONE:-"us-central1-a"}}
PROJECT_ID=${3:-${PROJECT_ID}}

# Validate inputs
if [ -z "$VM_NAME" ]; then
    print_error "VM name is required!"
    echo ""
    echo "Usage: $0 <vm-name> [zone] [project-id]"
    echo "   or: export VM_NAME=chatbot-vm && $0"
    echo ""
    echo "Example:"
    echo "  $0 chatbot-vm us-central1-a my-project-id"
    exit 1
fi

# Check if gcloud is installed
if ! command -v gcloud &> /dev/null; then
    print_error "gcloud CLI is not installed or not in PATH"
    echo "Install from: https://cloud.google.com/sdk/docs/install"
    exit 1
fi

# Check if authenticated
if ! gcloud auth list --filter=status:ACTIVE --format="value(account)" | grep -q .; then
    print_warn "Not authenticated with gcloud"
    echo "Running: gcloud auth login"
    gcloud auth login
fi

# Set project if provided
if [ -n "$PROJECT_ID" ]; then
    print_info "Setting GCP project to: $PROJECT_ID"
    gcloud config set project "$PROJECT_ID"
fi

# Get current project
CURRENT_PROJECT=$(gcloud config get-value project 2>/dev/null)
if [ -z "$CURRENT_PROJECT" ]; then
    print_error "No GCP project set. Please set it:"
    echo "  gcloud config set project YOUR_PROJECT_ID"
    echo "  or pass it as third argument: $0 $VM_NAME $VM_ZONE YOUR_PROJECT_ID"
    exit 1
fi

print_info "Using project: $CURRENT_PROJECT"

# Get script and project directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

# Detect if we're on Windows (Git Bash, WSL, etc.)
if [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" || -n "$WSL_DISTRO_NAME" ]]; then
    IS_WINDOWS=true
    # Convert Windows path to Unix-style if needed
    if [[ "$PROJECT_ROOT" == *"\\"* ]]; then
        PROJECT_ROOT=$(echo "$PROJECT_ROOT" | sed 's/\\/\//g' | sed 's/^C:/\/c/g')
    fi
else
    IS_WINDOWS=false
fi

# Verify project root exists and contains deployment directory
if [ ! -d "$PROJECT_ROOT" ]; then
    print_error "Project root not found: $PROJECT_ROOT"
    exit 1
fi

if [ ! -d "$PROJECT_ROOT/deployment" ]; then
    print_error "Deployment directory not found: $PROJECT_ROOT/deployment"
    print_error "Please run this script from the deployment directory or ensure the project structure is correct"
    exit 1
fi

print_info "Project root verified: $PROJECT_ROOT"

print_info "=========================================="
print_info "Deploying to Google Cloud VM"
print_info "=========================================="
print_info "VM Name: $VM_NAME"
print_info "Zone: $VM_ZONE"
print_info "Project: $CURRENT_PROJECT"
print_info "Source: $PROJECT_ROOT"
print_info ""

# Check if VM exists
print_info "Checking if VM exists..."
if ! gcloud compute instances describe "$VM_NAME" --zone="$VM_ZONE" --format="value(name)" &>/dev/null; then
    print_error "VM '$VM_NAME' not found in zone '$VM_ZONE'"
    echo ""
    echo "Available VMs:"
    gcloud compute instances list --format="table(name,zone,status)" || true
    exit 1
fi

# Check VM status
VM_STATUS=$(gcloud compute instances describe "$VM_NAME" --zone="$VM_ZONE" --format="value(status)")
if [ "$VM_STATUS" != "RUNNING" ]; then
    print_warn "VM is not running (status: $VM_STATUS)"
    read -p "Do you want to start the VM? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Starting VM..."
        gcloud compute instances start "$VM_NAME" --zone="$VM_ZONE"
        print_info "Waiting for VM to be ready..."
        sleep 10
    else
        print_error "VM must be running to deploy"
        exit 1
    fi
fi

# Step 1: Transfer files
print_info ""
print_info "Step 1: Transferring files to VM..."
print_info "This may take a few minutes..."
print_info "Source: $PROJECT_ROOT"

# Check if we're on Windows - gcloud scp might have issues with exclusions
if [[ "$IS_WINDOWS" == "true" ]]; then
    print_warn "Running on Windows - using simple transfer (no exclusions)"
    USE_EXCLUSIONS=false
else
    USE_EXCLUSIONS=true
fi

# Create a temporary file list for rsync-like exclusions
if [ "$USE_EXCLUSIONS" = true ]; then
    EXCLUDE_FILE=$(mktemp 2>/dev/null || echo /tmp/gcp-exclude-$$)
    cat > "$EXCLUDE_FILE" <<EOF
__pycache__/
*.pyc
*.pyo
*.pyd
.Python
*.so
*.egg
*.egg-info/
dist/
build/
.git/
.env
*.log
*.db
*.db-journal
*.db-wal
*.db-shm
node_modules/
.pytest_cache/
*.swp
*.swo
*~
.vscode/
.idea/
EOF
else
    EXCLUDE_FILE=""
fi

# Transfer files
print_info "Transferring: $PROJECT_ROOT -> ${VM_NAME}:~/GenAIChatbot"

TRANSFER_SUCCESS=false

# Try transfer with exclusions first (if not on Windows)
if [ "$USE_EXCLUSIONS" = true ]; then
    print_info "Attempting transfer with exclusions..."
    if gcloud compute scp --recurse \
        --exclude-from="$EXCLUDE_FILE" \
        "$PROJECT_ROOT" \
        "${VM_NAME}:~/GenAIChatbot" \
        --zone="$VM_ZONE" 2>&1; then
        TRANSFER_SUCCESS=true
    else
        print_warn "Transfer with exclusions failed, trying without exclusions..."
    fi
fi

# If first attempt failed or if directory doesn't exist, try without exclusions
if [ "$TRANSFER_SUCCESS" = false ] || ! gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --command="test -d ~/GenAIChatbot/deployment" 2>/dev/null; then
    print_info "Transferring files (without exclusions)..."
    print_info "This may take longer but is more reliable..."
    
    # Clean up any partial transfer first
    gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" \
        --command="rm -rf ~/GenAIChatbot" 2>/dev/null || true
    
    if gcloud compute scp --recurse \
        "$PROJECT_ROOT" \
        "${VM_NAME}:~/GenAIChatbot" \
        --zone="$VM_ZONE" 2>&1; then
        TRANSFER_SUCCESS=true
    else
        print_error "File transfer failed!"
        print_error "Please check:"
        print_error "  1. VM is running and accessible"
        print_error "  2. You have proper permissions"
        print_error "  3. Network connectivity is working"
        # Clean up exclude file if it was created
        if [ -n "$EXCLUDE_FILE" ] && [ -f "$EXCLUDE_FILE" ]; then
            rm -f "$EXCLUDE_FILE"
        fi
        exit 1
    fi
fi

# Clean up exclude file (only if it was created)
if [ "$USE_EXCLUSIONS" = true ] && [ -n "$EXCLUDE_FILE" ] && [ -f "$EXCLUDE_FILE" ]; then
    rm -f "$EXCLUDE_FILE"
fi

# Verify transfer succeeded
print_info "Verifying file transfer..."
if gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --command="
    if [ -d ~/GenAIChatbot/deployment ] && [ -f ~/GenAIChatbot/deployment/install.sh ]; then
        echo 'SUCCESS'
        ls -la ~/GenAIChatbot/deployment/ | head -10
    else
        echo 'FAILED'
        echo 'Directory structure:'
        ls -la ~/GenAIChatbot/ 2>&1 || echo 'GenAIChatbot directory does not exist'
        exit 1
    fi
" 2>&1 | grep -q "SUCCESS"; then
    print_info "✓ Files transferred and verified successfully"
else
    print_error "File transfer verification failed!"
    print_error "Please check the VM and ensure files were transferred correctly"
    # Clean up exclude file if it was created
    if [ "$USE_EXCLUSIONS" = true ] && [ -n "$EXCLUDE_FILE" ] && [ -f "$EXCLUDE_FILE" ]; then
        rm -f "$EXCLUDE_FILE"
    fi
    exit 1
fi

# Clean up exclude file (only if it was created)
if [ "$USE_EXCLUSIONS" = true ] && [ -n "$EXCLUDE_FILE" ] && [ -f "$EXCLUDE_FILE" ]; then
    rm -f "$EXCLUDE_FILE"
fi

# Step 2: Run installation on VM
print_info ""
print_info "Step 2: Running installation on VM..."
print_info "This will install system dependencies (Python, Node.js, Nginx, etc.)"

gcloud compute ssh "$VM_NAME" \
    --zone="$VM_ZONE" \
    --command="
        set -e
        echo 'Current directory: \$(pwd)'
        echo 'Home directory: \$HOME'
        echo 'Checking for GenAIChatbot directory...'
        
        if [ ! -d ~/GenAIChatbot ]; then
            echo 'ERROR: ~/GenAIChatbot directory does not exist'
            echo 'Listing home directory:'
            ls -la ~/
            exit 1
        fi
        
        if [ ! -d ~/GenAIChatbot/deployment ]; then
            echo 'ERROR: ~/GenAIChatbot/deployment directory does not exist'
            echo 'Listing GenAIChatbot directory:'
            ls -la ~/GenAIChatbot/
            exit 1
        fi
        
        cd ~/GenAIChatbot/deployment
        echo 'Changed to: \$(pwd)'
        echo 'Listing deployment directory:'
        ls -la
        
        if [ ! -f install.sh ]; then
            echo 'ERROR: install.sh not found in deployment directory'
            exit 1
        fi
        
        echo 'Running install.sh...'
        sudo bash install.sh
    "

if [ $? -eq 0 ]; then
    print_info "✓ Installation completed"
else
    print_error "Installation failed. Check the output above."
    exit 1
fi

# Step 3: Prompt for configuration
print_info ""
print_info "Step 3: Configuration required"
print_warn "You need to configure /etc/chatbot/.env with your API keys"
echo ""
echo "You can either:"
echo "  1. SSH into the VM and edit manually:"
echo "     gcloud compute ssh $VM_NAME --zone=$VM_ZONE"
echo "     sudo nano /etc/chatbot/.env"
echo ""
echo "  2. Or transfer a local .env file (if you have one):"
read -p "Do you have a local .env file to transfer? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    read -p "Enter path to your .env file: " ENV_FILE
    if [ -f "$ENV_FILE" ]; then
        print_info "Transferring .env file..."
        gcloud compute scp "$ENV_FILE" "${VM_NAME}:/tmp/.env" --zone="$VM_ZONE"
        gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" \
            --command="sudo mv /tmp/.env /etc/chatbot/.env && sudo chmod 600 /etc/chatbot/.env && sudo chown chatbot:chatbot /etc/chatbot/.env"
        print_info "✓ .env file transferred"
    else
        print_error "File not found: $ENV_FILE"
    fi
fi

# Step 4: Deploy application
print_info ""
print_info "Step 4: Deploying application..."
print_warn "Make sure /etc/chatbot/.env is configured before proceeding!"

read -p "Continue with deployment? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_warn "Deployment paused. Run the following when ready:"
    echo ""
    echo "  gcloud compute ssh $VM_NAME --zone=$VM_ZONE"
    echo "  cd ~/GenAIChatbot/deployment"
    echo "  sudo bash deploy.sh"
    exit 0
fi

gcloud compute ssh "$VM_NAME" \
    --zone="$VM_ZONE" \
    --command="
        set -e
        cd ~/GenAIChatbot/deployment
        
        if [ ! -f deploy.sh ]; then
            echo 'ERROR: deploy.sh not found'
            exit 1
        fi
        
        echo 'Running deploy.sh...'
        sudo bash deploy.sh
    "

if [ $? -eq 0 ]; then
    print_info "✓ Deployment completed"
else
    print_error "Deployment failed. Check the output above."
    exit 1
fi

# Step 5: Verify deployment
print_info ""
print_info "Step 5: Verifying deployment..."

gcloud compute ssh "$VM_NAME" \
    --zone="$VM_ZONE" \
    --command="
        cd ~/GenAIChatbot/deployment
        if [ -f post_install.sh ]; then
            sudo bash post_install.sh
        else
            echo 'Running basic verification...'
            sudo systemctl status chatbot.service --no-pager -l | head -20
        fi
    "

# Get VM external IP
print_info ""
print_info "=========================================="
print_info "Deployment Summary"
print_info "=========================================="

EXTERNAL_IP=$(gcloud compute instances describe "$VM_NAME" \
    --zone="$VM_ZONE" \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)")

if [ -n "$EXTERNAL_IP" ]; then
    print_info "VM External IP: $EXTERNAL_IP"
    print_info "Application URL: http://$EXTERNAL_IP"
    echo ""
    print_warn "Make sure firewall allows HTTP traffic (port 80):"
    echo "  gcloud compute firewall-rules create allow-http \\"
    echo "    --allow tcp:80 \\"
    echo "    --source-ranges 0.0.0.0/0 \\"
    echo "    --description 'Allow HTTP traffic'"
else
    print_warn "No external IP found. VM may only have internal IP."
fi

print_info ""
print_info "Useful commands:"
echo "  SSH to VM:     gcloud compute ssh ${VM_NAME} --zone=${VM_ZONE}"
echo "  View logs:     gcloud compute ssh ${VM_NAME} --zone=${VM_ZONE} --command=\"sudo journalctl -u chatbot -f\""
echo "  Restart:       gcloud compute ssh ${VM_NAME} --zone=${VM_ZONE} --command=\"sudo systemctl restart chatbot\""
echo "  Check status:  gcloud compute ssh ${VM_NAME} --zone=${VM_ZONE} --command=\"sudo systemctl status chatbot\""
echo ""

print_info "Deployment complete! ✓"
