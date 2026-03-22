# Chatbot Deployment Guide

This guide explains how to deploy the Generative AI Chatbot service to a Ubuntu Linux VM for PoC (Proof of Concept) purposes.

## Overview

This deployment package provides a simplified PoC setup using:
- **Flask built-in development server** (simpler setup, suitable for PoC)
- **Nginx reverse proxy** (security and static file serving)
- **Systemd service management** (auto-start and process management)
- **Node.js support** (for MCP servers)

## Prerequisites

- Ubuntu 20.04 or 22.04 LTS
- Root or sudo access
- Internet connection for package installation
- API keys for your chosen LLM provider (OpenAI, Gemini, or DeepSeek)

## Quick Start

### 1. Prepare Your VM

```bash
# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Ensure you have the deployment package
# The deployment/ directory should contain all deployment files
```

### 2. Run Installation

```bash
cd deployment
sudo bash install.sh
```

This will:
- Install Python 3.10+, Node.js 18+, and Nginx
- Create the `chatbot` user and directory structure
- Set up systemd service and Nginx configuration
- Install Python dependencies

### 3. Configure Environment

Edit the environment file with your actual configuration:

```bash
sudo nano /etc/chatbot/.env
```

**Required settings:**
- `LLM_PROVIDER` - Choose: `openai`, `gemini`, or `deepseek`
- `OPENAI_API_KEY` (if using OpenAI)
- `GEMINI_API_KEY` (if using Gemini)
- `DEEPSEEK_API_KEY` (if using DeepSeek)
- `JWT_SECRET_KEY` - Change to a strong random string!

**Optional settings:**
- Jira configuration (if using Jira integration)
- RAG configuration
- Memory management settings

### 4. Deploy Application

```bash
cd deployment
sudo bash deploy.sh
```

This will:
- Copy application files to `/opt/chatbot/generative-ai-chatbot`
- Set up data directories
- Start the chatbot service
- Reload Nginx

### 5. Verify Deployment

```bash
cd deployment
sudo bash post_install.sh
```

This will check:
- Service status
- Flask application response
- Nginx configuration
- Directory structure
- Configuration file

## Deploying to Google Cloud VM

### Prerequisites

- Google Cloud SDK (gcloud CLI) installed locally
- Authenticated with GCP: `gcloud auth login`
- VM created with Ubuntu 20.04/22.04 LTS
- VM has external IP (or configure internal access)
- Firewall rules configured (allow HTTP port 80)

### Quick Deployment Using deploy-to-gcp.sh

The easiest way to deploy to GCP is using the automated script:

1. **Make the script executable:**
   ```bash
   chmod +x deployment/deploy-to-gcp.sh
   ```

2. **Run the deployment script:**
   ```bash
   # Option 1: Pass parameters directly
   ./deployment/deploy-to-gcp.sh chatbot-vm us-central1-a my-project-id
   
   # Option 2: Use environment variables
   export VM_NAME=chatbot-vm
   export VM_ZONE=us-central1-a
   export PROJECT_ID=my-project-id
   ./deployment/deploy-to-gcp.sh
   ```

The script will:
- ✅ Check if VM exists and is running
- ✅ Transfer all files to the VM
- ✅ Run installation automatically
- ✅ Prompt for configuration
- ✅ Deploy the application
- ✅ Verify deployment
- ✅ Show VM IP and access URL

### Manual Deployment Steps

If you prefer manual deployment:

1. **Set your GCP variables:**
   ```bash
   export VM_NAME="chatbot-vm"
   export VM_ZONE="us-central1-a"
   export PROJECT_ID="your-project-id"
   ```

2. **Transfer files to VM:**
   ```bash
   # From your local workspace (Windows PowerShell)
   gcloud compute scp --recurse `
       C:\SourceCode\GenAIChatbot `
       ${VM_NAME}:~/GenAIChatbot `
       --zone=${VM_ZONE} `
       --project=${PROJECT_ID}
   
   # Or from Linux/Mac/Git Bash
   gcloud compute scp --recurse \
       ~/GenAIChatbot \
       ${VM_NAME}:~/GenAIChatbot \
       --zone=${VM_ZONE} \
       --project=${PROJECT_ID}
   ```

3. **SSH into VM:**
   ```bash
   gcloud compute ssh ${VM_NAME} --zone=${VM_ZONE}
   ```

4. **Run deployment on VM:**
   ```bash
   cd ~/GenAIChatbot/deployment
   sudo bash install.sh
   sudo nano /etc/chatbot/.env  # Configure your API keys
   sudo bash deploy.sh
   sudo bash post_install.sh
   ```

### GCP-Specific Configuration

#### 1. Create Firewall Rule

Allow HTTP traffic to your VM:

```bash
gcloud compute firewall-rules create allow-http \
    --allow tcp:80 \
    --source-ranges 0.0.0.0/0 \
    --description "Allow HTTP traffic" \
    --project=${PROJECT_ID}
```

#### 2. Reserve Static IP (Optional)

For a persistent IP address:

```bash
# Reserve static IP
gcloud compute addresses create chatbot-ip \
    --region=us-central1 \
    --project=${PROJECT_ID}

# Get the IP address
STATIC_IP=$(gcloud compute addresses describe chatbot-ip \
    --region=us-central1 \
    --format="value(address)")

# Assign to VM (if not already assigned)
gcloud compute instances add-access-config ${VM_NAME} \
    --access-config-name="External NAT" \
    --address=${STATIC_IP} \
    --zone=${VM_ZONE} \
    --project=${PROJECT_ID}
```

#### 3. Update Nginx Configuration

If you have a domain name, update the Nginx config on the VM:

```bash
# SSH into VM
gcloud compute ssh ${VM_NAME} --zone=${VM_ZONE}

# Edit Nginx config
sudo nano /etc/nginx/sites-available/chatbot

# Change server_name from _ to your domain:
# server_name your-domain.com;

# Test and reload
sudo nginx -t
sudo systemctl reload nginx
```

#### 4. Get VM External IP

```bash
# Get external IP
gcloud compute instances describe ${VM_NAME} \
    --zone=${VM_ZONE} \
    --format="get(networkInterfaces[0].accessConfigs[0].natIP)"
```

### Updating Application on GCP VM

For subsequent updates:

1. **Transfer updated files:**
   ```bash
   gcloud compute scp --recurse \
       C:\SourceCode\GenAIChatbot \
       ${VM_NAME}:~/GenAIChatbot \
       --zone=${VM_ZONE}
   ```

2. **SSH and redeploy:**
   ```bash
   gcloud compute ssh ${VM_NAME} --zone=${VM_ZONE}
   cd ~/GenAIChatbot/deployment
   sudo bash deploy.sh  # This will update and restart
   ```

### Windows Path Issues with gcloud scp

If you're on Windows and getting "unable to create directory" errors:

**Problem:** `gcloud compute scp` on Windows doesn't properly expand `~` in paths.

**Solution:** Use the helper script or absolute paths:

```bash
# Option 1: Use the helper script (recommended)
chmod +x deployment/transfer-files.sh
./deployment/transfer-files.sh instance-20260120-134255 us-central1-c gen-lang-client-0896070179

# Option 2: Get home directory and use absolute path
VM_HOME=$(gcloud compute ssh instance-20260120-134255 --zone=us-central1-c --command="echo \$HOME" | tr -d '\r\n')
gcloud compute scp --recurse /c/SourceCode/GenAIChatbot instance-20260120-134255:${VM_HOME}/GenAIChatbot --zone=us-central1-c

# Option 3: Transfer to /tmp first, then move
gcloud compute scp --recurse /c/SourceCode/GenAIChatbot instance-20260120-134255:/tmp/GenAIChatbot --zone=us-central1-c
gcloud compute ssh instance-20260120-134255 --zone=us-central1-c --command="mv /tmp/GenAIChatbot ~/GenAIChatbot"
```

### Proxy/Network Issues

If you encounter proxy errors when transferring files:

1. **Disable proxy in gcloud:**
   ```bash
   gcloud config set proxy/type none
   ```

2. **Or use alternative transfer methods:**
   - **Cloud Storage:** Upload to GCS bucket, download on VM
   - **Git:** Clone repository directly on VM
   - **Manual:** Use Cloud Console file upload

3. **Manual deployment on VM:**
   If files are already on the VM (transferred via other means):
   ```bash
   gcloud compute ssh instance-20260120-134255 --zone=us-central1-c
   cd ~/GenAIChatbot/deployment
   sudo bash deploy-on-vm.sh
   ```

See `TROUBLESHOOTING.md` for detailed proxy/network solutions.

### GCP Troubleshooting

#### VM Not Accessible

1. **Check firewall rules:**
   ```bash
   gcloud compute firewall-rules list --filter="name:allow-http"
   ```

2. **Check VM status:**
   ```bash
   gcloud compute instances describe ${VM_NAME} \
       --zone=${VM_ZONE} \
       --format="get(status)"
   ```

3. **Check if VM is running:**
   ```bash
   gcloud compute instances list --filter="name:${VM_NAME}"
   ```

#### View Logs Remotely

```bash
# View service logs
gcloud compute ssh ${VM_NAME} --zone=${VM_ZONE} \
    --command="sudo journalctl -u chatbot -n 50"

# Follow logs in real-time
gcloud compute ssh ${VM_NAME} --zone=${VM_ZONE} \
    --command="sudo journalctl -u chatbot -f"
```

#### Restart Service Remotely

```bash
gcloud compute ssh ${VM_NAME} --zone=${VM_ZONE} \
    --command="sudo systemctl restart chatbot"
```

## Directory Structure

After deployment, the following directories are created:

```
/opt/chatbot/generative-ai-chatbot/  # Application files
/var/log/chatbot/                     # Application logs
/var/lib/chatbot/data/                # Databases and data files
/etc/chatbot/                         # Configuration files
```

## Service Management

### Start/Stop/Restart Service

```bash
# Start service
sudo systemctl start chatbot

# Stop service
sudo systemctl stop chatbot

# Restart service
sudo systemctl restart chatbot

# Enable auto-start on boot
sudo systemctl enable chatbot

# Disable auto-start
sudo systemctl disable chatbot
```

### Check Service Status

```bash
# View status
sudo systemctl status chatbot

# View logs
sudo journalctl -u chatbot -f

# View last 50 lines
sudo journalctl -u chatbot -n 50
```

### Application Logs

```bash
# View application log
sudo tail -f /var/log/chatbot/app.log

# View Nginx access log
sudo tail -f /var/log/nginx/chatbot-access.log

# View Nginx error log
sudo tail -f /var/log/nginx/chatbot-error.log
```

## Accessing the Application

### Local Access

Once deployed, the application is accessible at:
- **HTTP**: `http://your-server-ip`
- **Local**: `http://localhost` (if accessing from the server)

### Firewall Configuration

If you have a firewall enabled, allow HTTP traffic:

```bash
# UFW (Ubuntu Firewall)
sudo ufw allow 80/tcp
sudo ufw reload

# Or for iptables
sudo iptables -A INPUT -p tcp --dport 80 -j ACCEPT
```

## Configuration Reference

### Environment Variables

All configuration is done via `/etc/chatbot/.env`. Key variables:

#### LLM Provider
- `LLM_PROVIDER` - Provider: `openai`, `gemini`, or `deepseek`
- `OPENAI_API_KEY` - OpenAI API key
- `OPENAI_MODEL` - Model name (e.g., `gpt-3.5-turbo`)
- `GEMINI_API_KEY` - Google Gemini API key
- `DEEPSEEK_API_KEY` - DeepSeek API key

#### Authentication
- `JWT_SECRET_KEY` - **REQUIRED**: Strong random secret for JWT tokens
- `JWT_EXPIRATION_HOURS` - Token expiration (default: 24)

#### Memory & RAG
- `USE_PERSISTENT_MEMORY` - Enable persistent conversation storage
- `USE_RAG` - Enable RAG (Retrieval-Augmented Generation)
- `RAG_VECTOR_STORE_PATH` - Path to vector store database

#### MCP Integration
- `USE_MCP` - Enable Model Context Protocol
- `ENABLE_MCP_TOOLS` - Enable MCP tools

See `.env.template` for all available options.

## Troubleshooting

### Service Won't Start

1. **Check service status:**
   ```bash
   sudo systemctl status chatbot
   ```

2. **Check logs:**
   ```bash
   sudo journalctl -u chatbot -n 50
   ```

3. **Check configuration:**
   ```bash
   sudo cat /etc/chatbot/.env
   ```

4. **Verify Python dependencies:**
   ```bash
   sudo -u chatbot python3 -c "import flask; print('Flask OK')"
   ```

### Flask App Not Responding

1. **Check if Flask is running:**
   ```bash
   sudo netstat -tlnp | grep 5000
   ```

2. **Test Flask directly:**
   ```bash
   curl http://127.0.0.1:5000
   ```

3. **Check application logs:**
   ```bash
   sudo tail -f /var/log/chatbot/app.log
   ```

### Nginx Issues

1. **Test Nginx configuration:**
   ```bash
   sudo nginx -t
   ```

2. **Check Nginx error log:**
   ```bash
   sudo tail -f /var/log/nginx/chatbot-error.log
   ```

3. **Reload Nginx:**
   ```bash
   sudo systemctl reload nginx
   ```

### Permission Issues

1. **Fix ownership:**
   ```bash
   sudo chown -R chatbot:chatbot /opt/chatbot/generative-ai-chatbot
   sudo chown -R chatbot:chatbot /var/log/chatbot
   sudo chown -R chatbot:chatbot /var/lib/chatbot
   ```

2. **Fix permissions:**
   ```bash
   sudo chmod 750 /opt/chatbot/generative-ai-chatbot
   sudo chmod 600 /etc/chatbot/.env
   ```

## Updating the Application

To update the application:

1. **Stop the service:**
   ```bash
   sudo systemctl stop chatbot
   ```

2. **Update application files:**
   ```bash
   sudo bash deploy.sh
   ```

3. **Start the service:**
   ```bash
   sudo systemctl start chatbot
   ```

## PoC Limitations

This deployment uses Flask's built-in development server, which has limitations:

- **Single-threaded**: Handles one request at a time
- **Not production-ready**: Suitable for PoC/demo only
- **Limited concurrency**: May experience delays under concurrent load

### For Production Use

For production deployments, consider:
- **Gunicorn** or **uWSGI** for better performance
- Multiple worker processes
- Process management and monitoring
- SSL/HTTPS setup (Let's Encrypt)
- Database optimization
- Caching layer (Redis)

## Security Considerations

1. **Change JWT Secret**: Always change `JWT_SECRET_KEY` to a strong random string
2. **Firewall**: Configure firewall to restrict access
3. **SSL/HTTPS**: Set up SSL certificates for production (Let's Encrypt)
4. **API Keys**: Never commit `.env` file with real API keys
5. **User Permissions**: Application runs as non-root user (`chatbot`)

## Additional Resources

- Application logs: `/var/log/chatbot/app.log`
- Systemd logs: `sudo journalctl -u chatbot`
- Nginx logs: `/var/log/nginx/chatbot-*.log`
- Configuration: `/etc/chatbot/.env`

## Support

For issues or questions:
1. Check the logs first
2. Review the troubleshooting section
3. Verify configuration settings
4. Check service status

## License

[Add your license information here]

