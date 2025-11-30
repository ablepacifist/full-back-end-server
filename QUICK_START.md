# Production Quick Start Guide

## 🚀 Quick Setup (10 minutes)

### ⚠️ CRITICAL: Use IP Addresses!
Remote users cannot resolve PlayIt.gg hostnames. You MUST use IP addresses in all configs!

### 1. Get your playit.gg tunnel IPs
```bash
# Start three tunnels (in separate terminals or background)
playit tunnel tcp 3001   # Frontend
playit tunnel tcp 8080   # Alchemy
playit tunnel tcp 36568  # Lexicon

# Get the ACTUAL IP addresses (not hostnames!)
nslookup lexicon.playit.pub        # Note the IP
nslookup gets-nintendo.gl.at.ply.gg  # Note the IP  
nslookup award-kirk.gl.at.ply.gg     # Note the IP
```

Example output:
```
Name:	lexicon.playit.pub
Address: 147.185.221.211    ← Use this IP in configs!
```

### 2. Configure environment files

**lexiconServer/.env** (use YOUR tunnel IPs!):
```properties
LEXICON_PORT=36568
SERVER_ADDRESS=0.0.0.0
CORS_ALLOWED_ORIGINS=http://147.185.221.211:58938,http://localhost:3001
MAX_FILE_SIZE=10GB
MAX_REQUEST_SIZE=10GB
UPLOAD_DIR=./uploads
DATABASE_URL=jdbc:hsqldb:hsql://localhost:9002/mydb
```

**alchemyServer/.env**:
```properties
ALCHEMY_PORT=8080
SERVER_ADDRESS=0.0.0.0
CORS_ALLOWED_ORIGINS=http://147.185.221.211:58938,http://localhost:3001
DATABASE_URL=jdbc:hsqldb:hsql://localhost:9002/mydb
```

**Lexicon/.env.production** (MUST use IP addresses!):
```properties
REACT_APP_API_URL=http://147.185.221.224:9675
REACT_APP_LEXICON_API_URL=http://147.185.221.224:9686
REACT_APP_FRONTEND_URL=http://147.185.221.211:58938
REACT_APP_ENV=production
```

### 3. Create start scripts

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

### 4. Build and start everything
```bash
# Build frontend
cd Lexicon && npm install && npm run build && cd ..

# Build backends
cd lexiconServer && ./gradlew build && cd ..
cd alchemyServer && ./gradlew build && cd ..

# Start all services (use master script)
./restart-all.sh
```

### 5. Access your app
Navigate to: `http://147.185.221.211:58938` (use YOUR frontend IP!)

## 🛑 Stop Services
```bash
pkill -f "alchemy.Main"
pkill -f "lexicon.LexiconApplication"
pkill -f "serve -s build"
```

## 📊 Check Status
```bash
# View logs
tail -f /tmp/alchemy-server.log
tail -f /tmp/lexicon-server.log
tail -f /tmp/frontend.log

# Check health
curl http://localhost:8080/api/health
curl http://localhost:36568/api/health

# Check database storage size
cd hsqldb && ls -lh mydb.lobs
# Shows actual file storage (e.g., 4.4G)
```

## 💾 Database Storage

Files are stored in `hsqldb/mydb.lobs` using BLOB (dynamic storage):
- 10MB file = 10MB stored
- 1.5GB file = 1.5GB stored
- No wasted space!

Monitor storage:
```bash
watch -n 5 'du -sh hsqldb/mydb.lobs'
```

## 🔧 Development vs Production

| Environment | Command | Uses |
|-------------|---------|------|
| Development | `npm start` | localhost URLs, hot reload |
| Production | `./start-production.sh` | playit.gg URLs, optimized build |

## 📝 Environment Variables Cheat Sheet

### Must Change for Production:
- `REACT_APP_API_URL` → Your alchemy tunnel **IP:PORT** (not hostname!)
- `REACT_APP_LEXICON_API_URL` → Your lexicon tunnel **IP:PORT** (not hostname!)
- `REACT_APP_FRONTEND_URL` → Your frontend tunnel **IP:PORT** (not hostname!)
- `CORS_ALLOWED_ORIGINS` → Your frontend tunnel **IP:PORT** (include both IP and hostname)

### Important Settings:
- `MAX_FILE_SIZE=10GB` - Maximum upload size (uses dynamic BLOB storage)
- `MAX_REQUEST_SIZE=10GB` - Maximum request size
- Timeout settings in application.properties (30 minutes for large uploads)

### Can Keep Defaults:
- Ports (3001, 8080, 36568, 9002)
- DATABASE_URL (if using localhost HSQLDB)
- UPLOAD_DIR (./uploads)

### Why IP Addresses?
Remote users get ERR_NAME_NOT_RESOLVED with PlayIt.gg hostnames. Always use:
- ✅ `http://147.185.221.224:9675` (IP address)
- ❌ `http://gets-nintendo.gl.at.ply.gg` (hostname - breaks for remote users)

Get IPs with: `nslookup your-tunnel.playit.gg`

## ⚠️ Common Issues

**CORS Error?**
- Check CORS_ALLOWED_ORIGINS uses IP addresses (not hostnames)
- Include both IP and hostname versions in CORS list
- No trailing slashes!
- Restart servers after changing (.env files must be reloaded)

**Can't access from remote network?**
- Use IP addresses, NOT playit.gg hostnames!
- Get IPs with `nslookup your-tunnel.playit.gg`
- Update all configs (.env.production, .env files) with IPs
- Rebuild frontend after changing IPs: `npm run build`

**Upload fails with ArrayIndexOutOfBounds?**
- FILE_DATA table must use BLOB (not VARBINARY)
- Run FixBlobTable.java to fix: `java -cp "hsqldb.jar:." FixBlobTable`

**File upload times out?**
- Check timeout settings in lexiconServer application.properties
- Should be 1800000ms (30 minutes) for large files
- Progress bar shows upload status

**Can't login?**
- Clear browser cookies
- Check database is running: `ps aux | grep hsqldb`
- Verify alchemy server accessible: `curl http://localhost:8080/api/health`
- Check CORS headers in browser dev tools

## 🔐 Security Checklist

- [ ] All 3 playit.gg tunnels configured
- [ ] CORS_ALLOWED_ORIGINS set correctly
- [ ] Frontend built with production config
- [ ] Database password changed from default
- [ ] Uploaded files directory secured
- [ ] Logs directory created

## 📦 Ports Reference

| Service | Local Port | Tunnel Example | Access Via |
|---------|------------|----------------|------------|
| Frontend | 3001 | 147.185.221.211:58938 | IP address |
| Alchemy | 8080 | 147.185.221.224:9675 | IP address |
| Lexicon | 36568 | 147.185.221.224:9686 | IP address |
| Database | 9002 | localhost only | Not public |

**Note**: Your tunnel IPs will be different! Use `nslookup` to find yours.

## 🎯 Testing Production Locally

Test with production URLs before deploying:
```bash
# Set prod env vars but use localhost
export CORS_ALLOWED_ORIGINS=http://localhost:3000
export REACT_APP_ENV=production

# Build and serve locally
cd Lexicon && npm run build
npx serve -s build -l 3000
```

## 📞 Quick Commands

```bash
# Build everything
cd lexiconServer && ./gradlew build
cd ../alchemyServer && ./gradlew build  
cd ../Lexicon && npm run build

# Check what's running
lsof -i :3000 :8080 :36568 :9002

# Kill specific port
kill $(lsof -ti:3000)
```
