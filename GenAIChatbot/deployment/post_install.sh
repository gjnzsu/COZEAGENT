#!/bin/bash
# Post-installation verification script
# This script verifies that the deployment was successful

set -e

echo "=========================================="
echo "Chatbot Deployment - Verification"
echo "=========================================="

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

ERRORS=0

# Check if chatbot service exists
echo ""
echo "1. Checking systemd service..."
if systemctl list-unit-files | grep -q chatbot.service; then
    echo "   ✓ Service file exists"
else
    echo "   ✗ Service file not found"
    ERRORS=$((ERRORS + 1))
fi

# Check service status
echo ""
echo "2. Checking service status..."
if systemctl is-active --quiet chatbot.service; then
    echo "   ✓ Service is running"
    systemctl status chatbot.service --no-pager -l | head -n 5
else
    echo "   ✗ Service is not running"
    ERRORS=$((ERRORS + 1))
    echo "   Check logs: sudo journalctl -u chatbot -n 50"
fi

# Check if Flask app is responding
echo ""
echo "3. Checking Flask application..."
sleep 2
if curl -s -f http://127.0.0.1:5000/ > /dev/null 2>&1; then
    echo "   ✓ Flask app is responding on port 5000"
elif curl -s -f http://127.0.0.1:5000/health > /dev/null 2>&1; then
    echo "   ✓ Flask app is responding (health check)"
else
    echo "   ✗ Flask app is not responding"
    echo "   Checking if Flask process is running..."
    if pgrep -f "run_production.py" > /dev/null; then
        echo "   ⚠ Flask process is running but not responding (may be starting up)"
    else
        echo "   ✗ Flask process is not running"
        ERRORS=$((ERRORS + 1))
    fi
fi

# Check Nginx configuration
echo ""
echo "4. Checking Nginx configuration..."
if nginx -t 2>&1 | grep -q "successful"; then
    echo "   ✓ Nginx configuration is valid"
else
    echo "   ✗ Nginx configuration has errors"
    ERRORS=$((ERRORS + 1))
    nginx -t
fi

# Check if Nginx is running
echo ""
echo "5. Checking Nginx service..."
if systemctl is-active --quiet nginx; then
    echo "   ✓ Nginx is running"
else
    echo "   ✗ Nginx is not running"
    ERRORS=$((ERRORS + 1))
fi

# Check if Nginx can reach Flask
echo ""
echo "6. Checking Nginx proxy..."
if curl -s -f http://127.0.0.1/ > /dev/null 2>&1; then
    echo "   ✓ Nginx can proxy to Flask app"
else
    echo "   ⚠ Nginx proxy test failed (may need firewall configuration)"
fi

# Check directories
echo ""
echo "7. Checking directories..."
DIRS=(
    "/opt/chatbot/generative-ai-chatbot"
    "/var/log/chatbot"
    "/var/lib/chatbot/data"
    "/etc/chatbot"
)

for DIR in "${DIRS[@]}"; do
    if [ -d "$DIR" ]; then
        echo "   ✓ $DIR exists"
    else
        echo "   ✗ $DIR missing"
        ERRORS=$((ERRORS + 1))
    fi
done

# Check environment file
echo ""
echo "8. Checking configuration file..."
if [ -f /etc/chatbot/.env ]; then
    echo "   ✓ Environment file exists"
    # Check if it has placeholder values
    if grep -q "your-" /etc/chatbot/.env 2>/dev/null; then
        echo "   ⚠ Warning: Environment file contains placeholder values"
        echo "   Please edit /etc/chatbot/.env and set your actual configuration"
    fi
else
    echo "   ✗ Environment file not found at /etc/chatbot/.env"
    ERRORS=$((ERRORS + 1))
fi

# Check log files
echo ""
echo "9. Checking log files..."
if [ -f /var/log/chatbot/app.log ]; then
    echo "   ✓ Application log file exists"
    echo "   Last few lines:"
    tail -n 3 /var/log/chatbot/app.log 2>/dev/null | sed 's/^/      /' || true
else
    echo "   ⚠ Application log file not found (may be created on first run)"
fi

# Check Node.js (for MCP)
echo ""
echo "10. Checking Node.js (for MCP servers)..."
if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    echo "   ✓ Node.js installed: $NODE_VERSION"
    if command -v npx &> /dev/null; then
        echo "   ✓ npx available for MCP servers"
    else
        echo "   ⚠ npx not found"
    fi
else
    echo "   ⚠ Node.js not installed (MCP servers may not work)"
fi

# Summary
echo ""
echo "=========================================="
if [ $ERRORS -eq 0 ]; then
    echo "✓ Verification complete - All checks passed!"
    echo "=========================================="
    echo ""
    echo "Service Information:"
    echo "  Service: chatbot.service"
    echo "  Status: $(systemctl is-active chatbot.service)"
    echo "  Logs: sudo journalctl -u chatbot -f"
    echo "  Application: http://$(hostname -I | awk '{print $1}')"
    echo ""
    echo "Useful commands:"
    echo "  Start service:   sudo systemctl start chatbot"
    echo "  Stop service:    sudo systemctl stop chatbot"
    echo "  Restart service: sudo systemctl restart chatbot"
    echo "  View logs:       sudo journalctl -u chatbot -f"
    echo "  Check status:    sudo systemctl status chatbot"
    exit 0
else
    echo "✗ Verification found $ERRORS issue(s)"
    echo "=========================================="
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check service logs: sudo journalctl -u chatbot -n 50"
    echo "  2. Check Nginx logs: sudo tail -f /var/log/nginx/chatbot-error.log"
    echo "  3. Verify configuration: sudo cat /etc/chatbot/.env"
    echo "  4. Check service status: sudo systemctl status chatbot"
    exit 1
fi

