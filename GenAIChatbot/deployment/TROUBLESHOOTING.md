# Deployment Troubleshooting Guide

## Proxy/Network Issues

### Error: ProxyError or Connection Reset

If you encounter proxy errors when using `gcloud compute scp`:

1. **Check proxy settings:**
   ```bash
   gcloud config get-value proxy/type
   gcloud config get-value proxy/address
   gcloud config get-value proxy/port
   ```

2. **Disable proxy if not needed:**
   ```bash
   gcloud config set proxy/type none
   ```

3. **Or configure proxy correctly:**
   ```bash
   gcloud config set proxy/type http
   gcloud config set proxy/address PROXY_HOST
   gcloud config set proxy/port PROXY_PORT
   ```

4. **Check environment variables:**
   ```bash
   # Windows PowerShell
   $env:HTTP_PROXY
   $env:HTTPS_PROXY
   
   # Unset if causing issues
   $env:HTTP_PROXY = ""
   $env:HTTPS_PROXY = ""
   ```

### Alternative: Manual File Transfer

If `gcloud compute scp` continues to fail, you can transfer files manually:

#### Method 1: Using Cloud Storage (Recommended)

1. **Upload to Cloud Storage:**
   ```bash
   # Create a bucket (one-time)
   gsutil mb gs://your-deployment-bucket
   
   # Upload files
   cd C:\SourceCode\GenAIChatbot
   tar -czf deployment.tar.gz --exclude='__pycache__' --exclude='*.pyc' --exclude='.git' .
   gsutil cp deployment.tar.gz gs://your-deployment-bucket/
   ```

2. **Download on VM:**
   ```bash
   # SSH into VM
   gcloud compute ssh instance-20260120-134255 --zone=us-central1-c
   
   # Download and extract
   gsutil cp gs://your-deployment-bucket/deployment.tar.gz ~/
   tar -xzf ~/deployment.tar.gz -C ~/GenAIChatbot
   ```

#### Method 2: Direct SSH with SCP (if proxy allows)

```bash
# Get VM external IP
gcloud compute instances describe instance-20260120-134255 \
    --zone=us-central1-c \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)"

# Use regular scp (if you have SSH key set up)
scp -r C:\SourceCode\GenAIChatbot user@VM_IP:~/GenAIChatbot
```

#### Method 3: Manual Upload via Cloud Console

1. Go to Cloud Console → Compute Engine → VM Instances
2. Click on your VM → SSH
3. In the SSH window, use the upload feature or manually create files

## File Transfer Workaround Script

If you're having persistent transfer issues, you can split the deployment:

1. **Transfer files manually** (using any method above)
2. **SSH into VM and run deployment scripts directly:**

```bash
# SSH into VM
gcloud compute ssh instance-20260120-134255 --zone=us-central1-c

# Once on VM, if files are already there:
cd ~/GenAIChatbot/deployment
sudo bash install.sh
sudo nano /etc/chatbot/.env  # Configure
sudo bash deploy.sh
sudo bash post_install.sh
```

## Common Issues

### VM Not Accessible

```bash
# Check VM status
gcloud compute instances describe instance-20260120-134255 \
    --zone=us-central1-c \
    --format="get(status)"

# Start VM if stopped
gcloud compute instances start instance-20260120-134255 --zone=us-central1-c
```

### Permission Issues

```bash
# Check if you have proper IAM roles
gcloud projects get-iam-policy gen-lang-client-0896070179 \
    --flatten="bindings[].members" \
    --filter="bindings.members:YOUR_EMAIL"
```

### Network/Firewall Issues

```bash
# Test connectivity
gcloud compute ssh instance-20260120-134255 --zone=us-central1-c \
    --command="echo 'Connection successful'"
```

## Quick Fix Commands

```bash
# Reset gcloud configuration
gcloud config unset proxy/type
gcloud config unset proxy/address
gcloud config unset proxy/port

# Test gcloud connectivity
gcloud compute instances list --zone=us-central1-c

# Check gcloud diagnostics
gcloud info --run-diagnostics
```

