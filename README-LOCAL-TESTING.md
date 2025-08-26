# Local Testing Guide

This guide explains how to test the WizKnowledge application locally.

## Prerequisites

- Python 3.7+ or Docker
- Git
- MongoDB (optional, can use Docker)

## Option 1: Run with Python (Simple)

### Quick Start
```bash
cd scripts
chmod +x run-app-locally.sh
./run-app-locally.sh
```

This script will:
- Create a Python virtual environment
- Install dependencies
- Start the Flask app on http://localhost:8080

### Manual Setup
```bash
cd app
python3 -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
python app.py
```

## Option 2: Run with Docker Compose (Full Stack)

This option includes MongoDB and Mongo Express for a complete local environment.

### Start all services:
```bash
docker-compose up
```

### Services will be available at:
- **App**: http://localhost:8080
- **MongoDB**: localhost:27017
- **Mongo Express**: http://localhost:8081 (admin/admin123)

### Stop services:
```bash
docker-compose down
```

### Clean up everything:
```bash
docker-compose down -v  # Also removes volumes/data
```

## Option 3: Connect to Dev Environment

To test against the actual dev MongoDB:

1. Get the dev MongoDB IP:
```bash
gcloud compute instances describe dev-mongodb-vm --zone=us-central1-a \
  --format="get(networkInterfaces[0].accessConfigs[0].natIP)"
```

2. Update your `.env` file:
```bash
MONGODB_URI=mongodb://admin:insecurepass@<DEV_IP>:27017/wizknowledge?authSource=admin
```

3. Run the app locally:
```bash
cd app
source venv/bin/activate
python app.py
```

## Testing the Application

### Basic Health Check
```bash
curl http://localhost:8080/
curl http://localhost:8080/health
```

### Test RAG Endpoint
```bash
curl -X POST http://localhost:8080/api/query \
  -H "Content-Type: application/json" \
  -d '{"query": "What is SQL injection?"}'
```

### Access the Web Interface
Open http://localhost:8080 in your browser

## Environment Variables

Create a `.env` file in the `app` directory:

```env
# Flask Configuration
FLASK_ENV=development
FLASK_DEBUG=1
PORT=8080

# MongoDB Configuration (choose one)
# Local MongoDB (Docker Compose)
MONGODB_URI=mongodb://admin:insecurepass@localhost:27017/wizknowledge?authSource=admin

# Remote Dev MongoDB
# MONGODB_URI=mongodb://admin:insecurepass@<DEV_IP>:27017/wizknowledge?authSource=admin

# No MongoDB (app will run without database)
# Leave MONGODB_URI unset

# Optional: API Keys for RAG features
# OPENAI_API_KEY=your-key-here
# GOOGLE_API_KEY=your-key-here
```

## Debugging

### Check logs:
```bash
# Python app logs
tail -f app.log

# Docker logs
docker-compose logs -f app
docker-compose logs -f mongodb
```

### Common Issues:

1. **Port already in use**:
   ```bash
   # Find process using port 8080
   lsof -i :8080
   # Kill it or use a different port
   export PORT=8888
   ```

2. **MongoDB connection failed**:
   - Check MongoDB is running: `docker ps`
   - Verify connection string in `.env`
   - Try connecting directly: `mongo mongodb://admin:insecurepass@localhost:27017`

3. **Module import errors**:
   ```bash
   pip install -r requirements.txt --upgrade
   ```

## Security Notes

⚠️ **For local testing only!** This setup includes:
- Weak passwords (admin/insecurepass)
- MongoDB without encryption
- Debug mode enabled
- CORS disabled

Never use these configurations in production!