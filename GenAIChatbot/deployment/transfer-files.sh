#!/bin/bash
# Helper script to transfer files to GCP VM
# This script handles Windows path issues and directory creation

set -e

VM_NAME=${1:-"instance-20260120-134255"}
VM_ZONE=${2:-"us-central1-c"}
PROJECT_ID=${3:-"gen-lang-client-0896070179"}

echo "Transferring files to GCP VM..."
echo "VM: $VM_NAME"
echo "Zone: $VM_ZONE"

# Get the actual home directory on the VM
echo "Getting VM home directory..."
VM_HOME=$(gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --project="$PROJECT_ID" \
    --command="echo \$HOME" 2>/dev/null | tr -d '\r\n' | tr -d ' ')

if [ -z "$VM_HOME" ]; then
    # Fallback: get username and construct path
    VM_USER=$(gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --project="$PROJECT_ID" \
        --command="whoami" 2>/dev/null | tr -d '\r\n' | tr -d ' ')
    VM_HOME="/home/$VM_USER"
    echo "Using fallback home: $VM_HOME"
else
    echo "VM home directory: $VM_HOME"
fi

# Create target directory
echo "Creating target directory on VM..."
gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --project="$PROJECT_ID" \
    --command="mkdir -p ${VM_HOME}/GenAIChatbot && chmod 755 ${VM_HOME}/GenAIChatbot" 2>&1

# Get project root (assuming script is in deployment/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo "Transferring from: $PROJECT_ROOT"
echo "Transferring to: ${VM_NAME}:${VM_HOME}/GenAIChatbot"

# Transfer files using absolute path
if gcloud compute scp --recurse \
    "$PROJECT_ROOT" \
    "${VM_NAME}:${VM_HOME}/GenAIChatbot" \
    --zone="$VM_ZONE" \
    --project="$PROJECT_ID" 2>&1; then
    echo "✓ Files transferred successfully!"
    
    # Verify transfer
    echo "Verifying transfer..."
    gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --project="$PROJECT_ID" \
        --command="ls -la ${VM_HOME}/GenAIChatbot/deployment/ | head -10" 2>&1
    
    echo ""
    echo "Files are now on the VM at: ${VM_HOME}/GenAIChatbot"
    echo "Next steps:"
    echo "  1. SSH into VM: gcloud compute ssh $VM_NAME --zone=$VM_ZONE"
    echo "  2. Run deployment: cd ~/GenAIChatbot/deployment && sudo bash deploy-on-vm.sh"
else
    echo "✗ Transfer failed. Trying alternative method..."
    
    # Alternative: Transfer to /tmp first
    echo "Trying alternative: transfer to /tmp first..."
    if gcloud compute scp --recurse \
        "$PROJECT_ROOT" \
        "${VM_NAME}:/tmp/GenAIChatbot" \
        --zone="$VM_ZONE" \
        --project="$PROJECT_ID" 2>&1; then
        echo "Files transferred to /tmp, moving to home directory..."
        gcloud compute ssh "$VM_NAME" --zone="$VM_ZONE" --project="$PROJECT_ID" \
            --command="rm -rf ${VM_HOME}/GenAIChatbot && mv /tmp/GenAIChatbot ${VM_HOME}/GenAIChatbot && chmod -R 755 ${VM_HOME}/GenAIChatbot" 2>&1
        echo "✓ Files successfully moved to ${VM_HOME}/GenAIChatbot"
    else
        echo "✗ Transfer failed completely"
        exit 1
    fi
fi

