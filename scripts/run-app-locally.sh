#!/bin/bash
# Script to run the Flask app locally for testing

set -e

echo "========================================="
echo "Setting up local development environment"
echo "========================================="

# Navigate to app directory
cd ../app

# Check Python version
echo "Checking Python version..."
python3 --version || {
    echo "❌ Python 3 is required. Please install Python 3.7+"
    exit 1
}

# Create virtual environment
echo "Creating virtual environment..."
if [ ! -d "venv" ]; then
    python3 -m venv venv
    echo "✅ Virtual environment created"
else
    echo "✅ Virtual environment already exists"
fi

# Activate virtual environment
echo "Activating virtual environment..."
source venv/bin/activate

# Install dependencies
echo "Installing dependencies..."
pip install --upgrade pip
pip install -r requirements.txt

# Set environment variables
echo "Setting environment variables..."
export FLASK_APP=app.py
export FLASK_ENV=development
export FLASK_DEBUG=1
export PORT=8080

# Optional: Set MongoDB connection (comment out if not needed)
# export MONGODB_URI="mongodb://localhost:27017/wizknowledge"

# Create a local .env file for testing (if doesn't exist)
if [ ! -f ".env" ]; then
    echo "Creating .env file for local testing..."
    cat > .env <<EOF
# Local development environment variables
FLASK_ENV=development
PORT=8080
# Add your MongoDB connection string if testing with database
# MONGODB_URI=mongodb://localhost:27017/wizknowledge
# MONGODB_URI=mongodb://admin:insecurepass@localhost:27017/wizknowledge?authSource=admin

# For testing with remote MongoDB (dev environment)
# MONGODB_URI=mongodb://admin:insecurepass@<DEV_MONGODB_IP>:27017/wizknowledge?authSource=admin

# Optional: Add API keys for testing
# OPENAI_API_KEY=your-key-here
# GOOGLE_API_KEY=your-key-here
EOF
    echo "✅ .env file created - please update with your configuration"
fi

echo ""
echo "========================================="
echo "Starting Flask application"
echo "========================================="
echo "App will be available at: http://localhost:8080"
echo "Debug mode is enabled - changes will auto-reload"
echo "Press Ctrl+C to stop the server"
echo ""

# Run the Flask app
python app.py