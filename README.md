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

Both Java servers now support environment variable overrides. Create `.env` files based on the templates:

#### **lexiconServer/.env**
```bash
cp lexiconServer/.env.example lexiconServer/.env
nano lexiconServer/.env
```

Edit with your production values:
```properties
# Server Configuration
LEXICON_PORT=36568
SERVER_ADDRESS=0.0.0.0

# Database Configuration
DATABASE_URL=jdbc:hsqldb:hsql://YOUR_DB_HOST:9002/mydb

# File Upload Configuration
MAX_FILE_SIZE=100MB
MAX_REQUEST_SIZE=100MB
UPLOAD_DIR=/var/app/uploads
```

#### **alchemyServer/.env**
```bash
cp alchemyServer/.env.example alchemyServer/.env
nano alchemyServer/.env
```

Edit with your production values:
```properties
# Server Configuration
ALCHEMY_PORT=8080
SERVER_ADDRESS=0.0.0.0

# Database Configuration
DATABASE_URL=jdbc:hsqldb:hsql://YOUR_DB_HOST:9002/mydb

# CORS Configuration
CORS_ALLOWED_ORIGINS=http://YOUR_PRODUCTION_IP:3000,http://YOUR_PRODUCTION_IP:3001,https://yourdomain.com
```

#### **Frontend Configuration**

**Lexicon/.env**
```properties
REACT_APP_API_URL=http://YOUR_PRODUCTION_IP:36568
PORT=3001
REACT_APP_ENV=production
```

**alchemyServer/alchemy-ui/.env**
```properties
REACT_APP_API_URL=http://YOUR_PRODUCTION_IP:8080
PORT=3000
```

### Step 3: Load Environment Variables

For the Java servers to read the `.env` files, you need to export them before starting:

```bash
# Option A: Source .env files manually
cd lexiconServer
export $(cat .env | xargs)
cd ../alchemyServer
export $(cat .env | xargs)

# Option B: Use systemd service files (recommended for production)
# See "Running as System Services" section below
```

### Step 4: Database Setup

```bash
# 1. Start HSQLDB (if not already running)
cd /path/to/hsqldb
java -cp hsqldb.jar org.hsqldb.server.Server \
  --database.0 file:/var/app/db/mydb \
  --dbname.0 mydb \
  --port 9002 &

# 2. Create media tables (one-time setup)
# Connect to HSQLDB and run:
sqlplus or use Java program to execute:

CREATE TABLE media_files (
    id INT PRIMARY KEY,
    uploaded_by INT NOT NULL,
    title VARCHAR(255) NOT NULL,
    description VARCHAR(1000),
    file_type VARCHAR(50),
    file_size BIGINT,
    upload_date TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    is_public BOOLEAN DEFAULT FALSE,
    tags VARCHAR(500)
);

CREATE TABLE file_data (
    media_file_id INT PRIMARY KEY,
    file_data BLOB,
    FOREIGN KEY (media_file_id) REFERENCES media_files(id) ON DELETE CASCADE
);
```

### Step 5: Build and Deploy

```bash
# Build lexiconServer
cd lexiconServer
export $(cat .env | xargs)
./mvnw clean package -DskipTests
java -jar target/lexiconServer-*.jar &

# Build alchemyServer
cd ../alchemyServer
export $(cat .env | xargs)
./mvnw clean package -DskipTests
java -jar target/alchemyServer-*.jar &

# Build and serve Alchemy UI
cd alchemy-ui
npm install
npm run build
npx serve -s build -p 3000 &

# Build and serve Lexicon UI
cd ../../Lexicon
npm install
npm run build
npx serve -s build -p 3001 &
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
