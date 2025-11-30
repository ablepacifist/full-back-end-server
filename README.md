# Full Stack Backend Server - Production Deployment Guide

This workspace contains multiple interconnected services that work together to provide a complete backend solution with media sharing capabilities.

## Repository Structure

```
full-back-end-server/
├── lexiconServer/       # Media sharing server (Port 36568)
├── alchemyServer/       # Main API server (Port 8080)
│   └── alchemy-ui/      # Alchemy frontend (Port 3000)
├── Lexicon/             # Lexicon frontend (Port 3001)
└── README.md            # This file
```

## Architecture Overview

- **HSQLDB**: Shared database server (Port 9002)
- **alchemyServer**: Main REST API with user authentication
- **lexiconServer**: Media file management and sharing platform
- **Alchemy UI**: React frontend for alchemy features
- **Lexicon UI**: React frontend for media management

All services share the same HSQLDB database for unified user management.

---

## Production Deployment

### Prerequisites

- Java 17 or higher
- Maven 3.6+
- Node.js 16+ and npm
- HSQLDB 2.7.x
- Git

### Step 1: Clone Repositories

```bash
# Choose a directory for your deployment
cd /opt/apps  # or wherever you want to deploy

# Clone all repositories
git clone https://github.com/ablepacifist/lexiconServer.git
git clone https://github.com/ablepacifist/alchemyServer.git
git clone https://github.com/ablepacifist/Lexicon.git

# For production, use main branch (after merging dev PRs)
# For testing latest features, use dev branch:
cd lexiconServer && git checkout dev && cd ..
cd alchemyServer && git checkout dev && cd ..
```

### Step 2: Configure Environment Variables

**CRITICAL: You must use IP addresses, not PlayIt.gg hostnames for remote access!**

Both Java servers now support environment variable overrides. Create `.env` files:

#### **Main Configuration (.env in root)**
Create `full-back-end-server/.env`:
```properties
# PlayIt.gg Tunnel IP Addresses (NOT hostnames!)
# Use nslookup to get IPs: nslookup your-tunnel.playit.gg
ALCHEMY_IP=147.185.221.224
ALCHEMY_PORT=9675
LEXICON_IP=147.185.221.224
LEXICON_PORT=9686
FRONTEND_IP=147.185.221.211
FRONTEND_PORT=58938

# Backend URLs (using IPs)
REACT_APP_API_URL=http://${ALCHEMY_IP}:${ALCHEMY_PORT}
REACT_APP_LEXICON_API_URL=http://${LEXICON_IP}:${LEXICON_PORT}
REACT_APP_FRONTEND_URL=http://${FRONTEND_IP}:${FRONTEND_PORT}

# CORS - include both IP and hostname versions
CORS_ALLOWED_ORIGINS=http://${FRONTEND_IP}:${FRONTEND_PORT},http://lexicon.playit.pub:58938,http://localhost:3001
```

#### **lexiconServer/.env**
```properties
# Server Configuration
LEXICON_PORT=36568
SERVER_ADDRESS=0.0.0.0

# CORS Configuration (use IPs!)
CORS_ALLOWED_ORIGINS=http://147.185.221.211:58938,http://lexicon.playit.pub:58938,http://localhost:3001

# File Upload Configuration (IMPORTANT for large files!)
MAX_FILE_SIZE=10GB
MAX_REQUEST_SIZE=10GB
UPLOAD_DIR=./uploads

# Database
DATABASE_URL=jdbc:hsqldb:hsql://localhost:9002/mydb

# yt-dlp cookies (optional, for age-restricted content)
YTDLP_COOKIES_PATH=./cookies.txt
```

**Note on file sizes**: The MAX_FILE_SIZE uses BLOB storage which is **dynamic** - a 10MB file takes 10MB, a 1.5GB file takes 1.5GB. No wasted space!

#### **Frontend Configuration (Lexicon/.env.production)**
```properties
# Backend URLs (MUST use IP addresses!)
REACT_APP_API_URL=http://147.185.221.224:9675
REACT_APP_LEXICON_API_URL=http://147.185.221.224:9686
REACT_APP_FRONTEND_URL=http://147.185.221.211:58938

# Environment
REACT_APP_ENV=production
```

### Step 3: Start Services with Environment Variables

**IMPORTANT**: Java servers must load .env files before starting!

#### **Create Start Scripts**

**lexiconServer/start.sh**:
```bash
#!/bin/bash
# Load environment variables from .env file
set -a
source .env
set +a

# Start the server
./gradlew bootRun
```

**alchemyServer/start.sh**:
```bash
#!/bin/bash
# Load environment variables from .env file
set -a
source .env
set +a

# Start the server
./gradlew bootRun
```

Make them executable:
```bash
chmod +x lexiconServer/start.sh
chmod +x alchemyServer/start.sh
```

#### **Master Restart Script**

Create `restart-all.sh` in the root directory:
```bash
#!/bin/bash

echo "Stopping all services..."
pkill -f "alchemy.Main"
pkill -f "lexicon.LexiconApplication"
pkill -f "serve -s build"
sleep 3

echo "Starting HSQLDB..."
cd hsqldb
java -cp hsqldb.jar org.hsqldb.server.Server --database.0 file:mydb --dbname.0 mydb --port 9002 &
sleep 5

echo "Starting AlchemyServer..."
cd ../alchemyServer
./start.sh > /tmp/alchemy-server.log 2>&1 &
sleep 10

echo "Starting LexiconServer..."
cd ../lexiconServer
./start.sh > /tmp/lexicon-server.log 2>&1 &
sleep 10

echo "Starting Frontend..."
cd ../Lexicon
nohup npx serve -s build -l 3001 > /tmp/frontend.log 2>&1 &

echo "All services started!"
echo "Check logs:"
echo "  tail -f /tmp/alchemy-server.log"
echo "  tail -f /tmp/lexicon-server.log"
echo "  tail -f /tmp/frontend.log"
```

```bash
chmod +x restart-all.sh
./restart-all.sh
```

### Step 4: Database Setup

```bash
# 1. Start HSQLDB (if not already running)
cd hsqldb
java -cp hsqldb.jar org.hsqldb.server.Server \
  --database.0 file:mydb \
  --dbname.0 mydb \
  --port 9002 &

# 2. Create media tables using provided script
# The CreateSchema.java will create both MEDIA_FILES and FILE_DATA tables
cd hsqldb
javac -cp hsqldb.jar CreateSchema.java
java -cp "hsqldb.jar:." CreateSchema

# 3. IMPORTANT: FILE_DATA must use BLOB for large files!
# The schema creates:
CREATE TABLE media_files (
    id INT PRIMARY KEY,
    filename VARCHAR(255),
    original_filename VARCHAR(255),
    content_type VARCHAR(100),
    file_size BIGINT,
    file_path VARCHAR(500),
    uploaded_by INT,
    title VARCHAR(255),
    description VARCHAR(1000),
    is_public BOOLEAN DEFAULT FALSE,
    upload_date TIMESTAMP,
    media_type VARCHAR(50),
    source_url VARCHAR(1000)
);

CREATE TABLE file_data (
    media_file_id INT PRIMARY KEY,
    data BLOB,  -- BLOB allows unlimited file sizes (dynamic storage!)
    FOREIGN KEY (media_file_id) REFERENCES media_files(id) ON DELETE CASCADE
);
```

**Why BLOB?** Using `BLOB` instead of `VARBINARY` provides dynamic storage - a 10MB file uses 10MB, a 1.5GB file uses 1.5GB. No wasted space or array size limits!

### Step 5: Build and Deploy

```bash
# Build lexiconServer
cd lexiconServer
./gradlew build
# Server will start via start.sh script

# Build alchemyServer
cd ../alchemyServer
./gradlew build
# Server will start via start.sh script

# Build and serve Lexicon UI
cd ../Lexicon
npm install
npm run build
npx serve -s build -l 3001 &
```

---

## Checking Database Storage Size

Your uploaded files are stored in the HSQLDB database. To check current storage:

```bash
cd hsqldb
ls -lh mydb*
```

You'll see:
- `mydb.lobs` - Contains all uploaded file data (BLOB storage)
- `mydb.script` - Contains table structures and metadata
- `mydb.log` - Transaction log

**Example output:**
```
-rw-rw-r-- 1 user user 4.4G Nov 29 18:20 mydb.lobs    # Your uploaded files
-rw-rw-r-- 1 user user 350M Nov 29 17:21 mydb.script  # Metadata
-rw-rw-r-- 1 user user  16K Nov 29 18:21 mydb.log     # Transaction log
```

The `mydb.lobs` file grows dynamically:
- Upload a 10MB file → grows by ~10MB
- Upload a 1.5GB file → grows by ~1.5GB
- Delete a file → space can be reclaimed

**Monitor storage:**
```bash
# Watch storage in real-time
watch -n 5 'du -sh hsqldb/mydb.lobs'

# Check total database size
du -sh hsqldb/
```

---

## Running as System Services (Recommended)

For production, use systemd services to manage the applications:

### Create Service Files

**lexiconServer.service**
```ini
[Unit]
Description=Lexicon Media Server
After=network.target hsqldb.service

[Service]
Type=simple
User=appuser
WorkingDirectory=/opt/apps/lexiconServer
EnvironmentFile=/opt/apps/lexiconServer/.env
ExecStart=/usr/bin/java -jar /opt/apps/lexiconServer/target/lexiconServer-*.jar
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

**alchemyServer.service**
```ini
[Unit]
Description=Alchemy API Server
After=network.target hsqldb.service

[Service]
Type=simple
User=appuser
WorkingDirectory=/opt/apps/alchemyServer
EnvironmentFile=/opt/apps/alchemyServer/.env
ExecStart=/usr/bin/java -jar /opt/apps/alchemyServer/target/alchemyServer-*.jar
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

### Enable and Start Services

```bash
sudo cp *.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable lexiconServer alchemyServer
sudo systemctl start lexiconServer alchemyServer
sudo systemctl status lexiconServer alchemyServer
```

---

## Testing the Deployment

```bash
# Test alchemyServer
curl http://localhost:8080/api/health

# Test lexiconServer
curl http://localhost:36568/api/media/public

# Test frontends
curl http://localhost:3000
curl http://localhost:3001
```

---

## Configuration Reference

### Environment Variables (Java Servers)

| Variable | Default | Description |
|----------|---------|-------------|
| `LEXICON_PORT` | 36568 | Lexicon server port |
| `ALCHEMY_PORT` | 8080 | Alchemy server port |
| `SERVER_ADDRESS` | 0.0.0.0 | Bind address (0.0.0.0 = all interfaces) |
| `DATABASE_URL` | jdbc:hsqldb:hsql://localhost:9002/mydb | HSQLDB connection string |
| `CORS_ALLOWED_ORIGINS` | http://localhost:3000,http://localhost:3001 | Comma-separated CORS origins |
| `MAX_FILE_SIZE` | 100MB | Maximum file upload size |
| `MAX_REQUEST_SIZE` | 100MB | Maximum request size |
| `UPLOAD_DIR` | ./uploads | Directory for uploaded files |

### Port Reference

| Service | Default Port | Environment Variable |
|---------|--------------|---------------------|
| HSQLDB | 9002 | N/A (hardcoded in DATABASE_URL) |
| alchemyServer | 8080 | ALCHEMY_PORT |
| lexiconServer | 36568 | LEXICON_PORT |
| Alchemy UI | 3000 | PORT (in .env) |
| Lexicon UI | 3001 | PORT (in .env) |

---

## Security Considerations

1. **Firewall Rules**: Only expose necessary ports
2. **HTTPS**: Use reverse proxy (nginx/Apache) with SSL certificates
3. **Database**: Don't expose HSQLDB port to internet
4. **Environment Files**: Never commit `.env` files to git
5. **File Permissions**: Restrict `.env` files to owner only:
   ```bash
   chmod 600 lexiconServer/.env alchemyServer/.env
   ```

---

## Troubleshooting

### Application won't start
```bash
# Check if environment variables are loaded
echo $DATABASE_URL

# Check if ports are available
sudo netstat -tlnp | grep -E '8080|36568|9002'

# Check logs
journalctl -u lexiconServer -f
journalctl -u alchemyServer -f
```

### Database connection issues
```bash
# Test HSQLDB connection
telnet YOUR_DB_HOST 9002

# Check HSQLDB is running
ps aux | grep hsqldb
```

### CORS errors in frontend
- Verify `CORS_ALLOWED_ORIGINS` includes your frontend URLs
- Check if frontend `.env` files have correct API URLs

---

## Updating Production

```bash
# Pull latest changes
cd lexiconServer && git pull && cd ..
cd alchemyServer && git pull && cd ..
cd Lexicon && git pull && cd ..

# Rebuild and restart
sudo systemctl restart lexiconServer alchemyServer

# Rebuild frontends
cd alchemyServer/alchemy-ui && npm run build
cd ../../Lexicon && npm run build
```

---

## Additional Resources

- **lexiconServer**: Media sharing platform with file upload/download
- **alchemyServer**: User authentication and main API
- **Shared Database**: Both servers use same HSQLDB instance
- **Test Suite**: 57+ tests ensure reliability

---
---

## Quick Start Checklist

- [ ] Clone all three repositories
- [ ] Copy `.env.example` to `.env` in both Java servers
- [ ] Update `.env` files with production values
- [ ] Create frontend `.env` files with correct API URLs
- [ ] Start HSQLDB database
- [ ] Create media tables in database
- [ ] Build and start Java servers (with env vars loaded)
- [ ] Build and serve frontends
- [ ] Test all endpoints
- [ ] Set up systemd services for production
- [ ] Configure reverse proxy with SSL

**No more hardcoded IPs! Just update your `.env` files and restart!**
