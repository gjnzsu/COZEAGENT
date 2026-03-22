#!/usr/bin/env python3
"""
Production runner script for Flask chatbot application.

This script runs the Flask app in production mode with:
- Debug mode disabled
- Reloader disabled
- Proper logging configuration
- Host bound to 127.0.0.1 (for Nginx proxy)
- Configurable port (default: 5000)
"""

import os
import sys
import logging
from pathlib import Path

# Verify we're using the virtual environment Python
venv_python = Path('/opt/chatbot/venv/bin/python3')
if venv_python.exists() and str(venv_python.resolve()) != sys.executable:
    # If we're not using venv Python, log a warning but continue
    # (systemd should be using venv Python via ExecStart)
    pass

# Add project root to path
project_root = Path(__file__).parent
sys.path.insert(0, str(project_root))

# Verify Flask is importable before trying to import app
try:
    import flask
    # Use importlib.metadata to avoid deprecation warning
    try:
        from importlib.metadata import version
        flask_version = version('flask')
    except:
        flask_version = getattr(flask, '__version__', 'unknown')
    logging.info(f"Flask {flask_version} is available")
except ImportError as e:
    logging.error(f"Flask is not available in Python environment: {e}")
    logging.error(f"Python executable: {sys.executable}")
    logging.error(f"Python path: {sys.path}")
    # Try to find Flask in common locations
    import site
    for site_packages in site.getsitepackages():
        flask_path = Path(site_packages) / 'flask'
        if flask_path.exists():
            logging.error(f"Found Flask at: {flask_path} (but not importable)")
    # Check venv site-packages
    venv_base = Path('/opt/chatbot/venv')
    if venv_base.exists():
        # Find Python version directory
        for py_dir in (venv_base / 'lib').glob('python*'):
            site_packages = py_dir / 'site-packages'
            if site_packages.exists():
                flask_path = site_packages / 'flask'
                if flask_path.exists():
                    logging.error(f"Flask directory exists at: {flask_path}")
                else:
                    logging.error(f"Flask directory NOT found at: {flask_path}")
    sys.exit(1)

# Configure logging
log_dir = Path('/var/log/chatbot')
log_dir.mkdir(parents=True, exist_ok=True)

# Set up file logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(log_dir / 'app.log'),
        logging.StreamHandler(sys.stdout)
    ]
)

logger = logging.getLogger(__name__)

# Import Flask app
try:
    from app import app
    logger.info("Flask app imported successfully")
except ImportError as e:
    logger.error(f"Failed to import Flask app: {e}")
    sys.exit(1)

def main():
    """Run Flask app in production mode."""
    # Get configuration from environment
    host = os.getenv('FLASK_HOST', '127.0.0.1')
    port = int(os.getenv('FLASK_PORT', '5000'))
    debug = os.getenv('FLASK_DEBUG', 'False').lower() == 'true'
    
    logger.info("=" * 70)
    logger.info("🤖 Chatbot Web UI - Production Mode")
    logger.info("=" * 70)
    logger.info(f"Host: {host}")
    logger.info(f"Port: {port}")
    logger.info(f"Debug: {debug}")
    logger.info("=" * 70)
    
    try:
        # Run Flask app in production mode
        app.run(
            host=host,
            port=port,
            debug=debug,
            use_reloader=False,  # Disable reloader in production
            threaded=True  # Enable threading for better concurrency
        )
    except KeyboardInterrupt:
        logger.info("Shutting down gracefully...")
        sys.exit(0)
    except Exception as e:
        logger.error(f"Failed to start Flask app: {e}", exc_info=True)
        sys.exit(1)

if __name__ == '__main__':
    main()

