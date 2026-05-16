# Production Deployment Guide

## Prerequisites
- playit.gg account and client installed
- Java 21+ installed
- Node.js 18+ installed
- HSQLDB running

## ⚠️ CRITICAL: Use IP Addresses, NOT Hostnames!

Remote users cannot resolve PlayIt.gg hostnames due to DNS issues. You MUST use IP addresses in all configurations.

### Get Your Tunnel IP Addresses

For each tunnel, find the actual IP:
```bash
nslookup gets-nintendo.gl.at.ply.gg
nslookup award-kirk.gl.at.ply.gg
nslookup lexicon.playit.pub
```

Example output:
```
Server:		127.0.0.53
Address:	127.0.0.53#53

Non-authoritative answer:
Name:	gets-nintendo.gl.at.ply.gg
Address: 147.185.221.224    ← Use this IP!
```

## Step 1: Set up playit.gg Tunnels

You'll need **3 tunnels**:

1. **Frontend Tunnel** (local port 3001)
   ```bash
   playit tunnel tcp 3001
   ```
   Note the hostname AND resolve to IP: `nslookup lexicon.playit.pub`

2. **Alchemy Server Tunnel** (local port 8080)
   ```bash
   playit tunnel tcp 8080
   ```
   Note the hostname AND resolve to IP: `nslookup gets-nintendo.gl.at.ply.gg`

3. **Lexicon Server Tunnel** (local port 36568)
   ```bash
   playit tunnel tcp 36568
   ```
   Note the hostname AND resolve to IP: `nslookup award-kirk.gl.at.ply.gg`

## Step 2: Configure Environment Variables

### Frontend (Lexicon React App)

Create `Lexicon/.env.production` (NOT .env.production.local):

```properties
# Backend API URLs (MUST use IP addresses!)
REACT_APP_API_URL=http://147.185.221.224:9675
REACT_APP_LEXICON_API_URL=http://147.185.221.224:9686

# Frontend URL (use IP)
REACT_APP_FRONTEND_URL=http://147.185.221.211:58938

# Environment
REACT_APP_ENV=production
```

**Replace the IPs above with YOUR tunnel IPs from nslookup!**

### Backend - lexiconServer/.env

```properties
# Server Configuration
LEXICON_PORT=36568
SERVER_ADDRESS=0.0.0.0

# CORS Configuration (MUST use IPs!)
CORS_ALLOWED_ORIGINS=http://147.185.221.211:58938,http://lexicon.playit.pub:58938,http://localhost:3001

# File Upload Configuration - 10GB limit with BLOB storage
MAX_FILE_SIZE=10GB
MAX_REQUEST_SIZE=10GB
UPLOAD_DIR=./uploads

# Timeout for large files (30 minutes)
server.tomcat.connection-timeout=1800000
spring.mvc.async.request-timeout=1800000

# Database
DATABASE_URL=jdbc:hsqldb:hsql://localhost:9002/mydb

# yt-dlp (optional)
YTDLP_COOKIES_PATH=./cookies.txt
```

### Backend - alchemyServer/.env

```properties
# Server Configuration
ALCHEMY_PORT=8080
SERVER_ADDRESS=0.0.0.0

# CORS Configuration (use IPs!)
CORS_ALLOWED_ORIGINS=http://147.185.221.211:58938,http://lexicon.playit.pub:58938,http://localhost:3001

# Database
DATABASE_URL=jdbc:hsqldb:hsql://localhost:9002/mydb
```

### Create Start Scripts

Both servers MUST load .env files before starting!

**lexiconServer/start.sh**:
```bash
#!/bin/bash
set -a
source .env
set +a
./gradlew bootRun
```

**alchemyServer/start.sh**:
```bash
#!/bin/bash
set -a
source .env
set +a
./gradlew bootRun
```

```bash
chmod +x lexiconServer/start.sh alchemyServer/start.sh
```

## Step 3: Build for Production

### Frontend
```bash
cd Lexicon
npm install
npm run build
```

This creates an optimized production build in `Lexicon/build/` using the IP addresses from `.env.production`

### Backend - lexiconServer
```bash
cd lexiconServer
./gradlew build
```

### Backend - alchemyServer
```bash
cd alchemyServer
./gradlew build
```

## Step 4: Database Setup

```bash
# Start HSQLDB server (if not running)
cd hsqldb
java -cp hsqldb.jar org.hsqldb.server.Server --database.0 file:mydb --dbname.0 mydb --port 9002 &

# Create tables (run once)
javac -cp hsqldb.jar CreateSchema.java
java -cp "hsqldb.jar:." CreateSchema
```

**IMPORTANT**: The FILE_DATA table MUST use BLOB type for large files:
```sql
CREATE TABLE file_data (
    media_file_id INT PRIMARY KEY,
    data BLOB,  -- Not VARBINARY! BLOB = unlimited size
    FOREIGN KEY (media_file_id) REFERENCES media_files(id) ON DELETE CASCADE
);
```

If you need to fix it:
```bash
cd hsqldb
javac -cp hsqldb.jar FixBlobTable.java
java -cp "hsqldb.jar:." FixBlobTable
```

## Step 5: Start All Services

### Master Restart Script (Recommended)

Create `restart-all.sh`:
```bash
#!/bin/bash

echo "Stopping all services..."
pkill -f "alchemy.Main"
pkill -f "lexicon.LexiconApplication"
pkill -f "serve -s build"
sleep 3

echo "Starting AlchemyServer..."
cd alchemyServer
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
```

```bash
chmod +x restart-all.sh
./restart-all.sh
```

### Manual Start (Alternative)

```bash
# Terminal 1: AlchemyServer
cd alchemyServer
./start.sh

# Terminal 2: LexiconServer  
cd lexiconServer
./start.sh

# Terminal 3: Frontend
cd Lexicon
npx serve -s build -l 3001
```

## Step 6: Access Your Application

Navigate to your frontend tunnel URL (using the IP address):
```
http://147.185.221.211:58938
```

Or try the hostname (may not work for remote users):
```
http://lexicon.playit.pub:58938
```

## Monitoring & Database Storage

### Check Database Size
```bash
cd hsqldb
ls -lh mydb*
```

Output shows:
- `mydb.lobs` = Your uploaded files (grows dynamically)
- `mydb.script` = Table structure and metadata
- `mydb.log` = Transaction log

Example:
```
-rw-rw-r-- 1 user user 4.4G Nov 29 18:20 mydb.lobs    # All uploaded files
-rw-rw-r-- 1 user user 350M Nov 29 17:21 mydb.script  # Metadata
-rw-rw-r-- 1 user user  16K Nov 29 18:21 mydb.log     # Log
```

**Monitor storage in real-time:**
```bash
watch -n 5 'du -sh hsqldb/mydb.lobs'
```

### Check Server Health
```bash
curl http://localhost:8080/api/health
curl http://localhost:36568/api/health
```

### View Logs
```bash
tail -f /tmp/alchemy-server.log
tail -f /tmp/lexicon-server.log
tail -f /tmp/frontend.log
```

### CORS Errors
- Verify `CORS_ALLOWED_ORIGINS` includes your frontend playit.gg URL
- Check that URLs don't have trailing slashes
- Restart servers after changing CORS config

### Connection Refused
- Verify all servers are running
- Check playit.gg tunnels are active
- Verify ports match configuration

### 401 Unauthorized
- Check cookies are being sent (credentials: 'include')
- Verify CORS allowCredentials is true
- Test login/registration flow

### File Upload Issues
- Verify upload directory exists and is writable
- Check MAX_FILE_SIZE and MAX_REQUEST_SIZE are sufficient
- Look for disk space issues

## Environment Switching

### Development
```bash
# Use .env.development (default)
npm start
```

### Production
```bash
# Use .env.production
npm run build
npx serve -s build
```

## Security Considerations for Production

1. **HTTPS**: playit.gg provides HTTPS automatically
2. **Database**: Consider moving to PostgreSQL for production
3. **File Storage**: Consider cloud storage (S3, etc.) for uploads
4. **Environment Variables**: Never commit `.env.production.local`
5. **Passwords**: Use strong database passwords
6. **Logs**: Set up proper logging and monitoring

## Backup Strategy

1. **Database**
   ```bash
   # Backup HSQLDB
   java -cp hsqldb.jar org.hsqldb.server.Server --database.0 file:mydb_backup --dbname.0 mydb
   ```

2. **Uploaded Files**
   ```bash
   # Backup uploads directory
   tar -czf uploads_backup_$(date +%Y%m%d).tar.gz uploads/
   ```

## Monitoring

Check server health:
```bash
curl https://your-alchemy.playit.gg/api/health
curl https://your-lexicon.playit.gg/api/health
```

## Quick Reference

| Service | Port | Tunnel URL | Purpose |
|---------|------|------------|---------|
| Frontend | 3000 | your-frontend.playit.gg | React app |
| Alchemy | 8080 | your-alchemy.playit.gg | Auth & game logic |
| Lexicon | 36568 | your-lexicon.playit.gg | Media management |
| Database | 9002 | localhost only | HSQLDB |
