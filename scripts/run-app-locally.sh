#!/bin/bash
# Script to run the Flask app locally for testing

set -e

cd ../app

# Check Python version
python3 --version || {
    echo "❌ Python 3 is required. Please install Python 3.7+"
    exit 1
}

# Setup virtual environment
[ ! -d "venv" ] && python3 -m venv venv
source venv/bin/activate
pip install -q --upgrade pip && pip install -q -r requirements.txt

# Set environment variables
export FLASK_APP=app.py FLASK_ENV=development FLASK_DEBUG=1 PORT=8080

# Create .env file if it doesn't exist
[ ! -f ".env" ] && cat > .env <<EOF
FLASK_ENV=development
PORT=8080
# MONGODB_URI=mongodb://localhost:27017/wizknowledge
EOF

echo "Starting Flask app at http://localhost:8080 (Press Ctrl+C to stop)"
python app.py