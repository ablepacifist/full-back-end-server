# Production Deployment Guide

## Prerequisites
- playit.gg account and client installed
- Java 17+ installed
- Node.js 18+ installed
- HSQLDB running

## Step 1: Set up playit.gg Tunnels

You'll need **3 tunnels**:

1. **Frontend Tunnel** (port 3000)
   ```bash
   playit tunnel tcp 3000
   ```
   Note the URL (e.g., `https://your-frontend.playit.gg`)

2. **Alchemy Server Tunnel** (port 8080)
   ```bash
   playit tunnel tcp 8080
   ```
   Note the URL (e.g., `https://your-alchemy.playit.gg`)

3. **Lexicon Server Tunnel** (port 36568)
   ```bash
   playit tunnel tcp 36568
   ```
   Note the URL (e.g., `https://your-lexicon.playit.gg`)

## Step 2: Configure Environment Variables

### Frontend (Lexicon React App)

Create `.env.production.local` in the `Lexicon/` directory:

```bash
# Backend API URLs (use your playit.gg tunnel URLs)
REACT_APP_API_URL=https://your-alchemy.playit.gg
REACT_APP_LEXICON_API_URL=https://your-lexicon.playit.gg

# Frontend URL
REACT_APP_FRONTEND_URL=https://your-frontend.playit.gg

# Environment
REACT_APP_ENV=production
PORT=3000
```

### Backend - lexiconServer

Create environment file or set these before running:

```bash
export LEXICON_PORT=36568
export SERVER_ADDRESS=0.0.0.0
export CORS_ALLOWED_ORIGINS=https://your-frontend.playit.gg
export DATABASE_URL=jdbc:hsqldb:hsql://localhost:9002/mydb
export UPLOAD_DIR=./uploads
export MAX_FILE_SIZE=100MB
export MAX_REQUEST_SIZE=100MB
```

Or create `lexiconServer/src/main/resources/application-production.properties`:

```properties
server.port=36568
server.address=0.0.0.0
cors.allowed.origins=https://your-frontend.playit.gg
database.url=jdbc:hsqldb:hsql://localhost:9002/mydb
lexicon.file.upload-dir=./uploads
spring.servlet.multipart.max-file-size=100MB
spring.servlet.multipart.max-request-size=100MB
```

### Backend - alchemyServer

```bash
export ALCHEMY_PORT=8080
export SERVER_ADDRESS=0.0.0.0
export CORS_ALLOWED_ORIGINS=https://your-frontend.playit.gg
export DATABASE_URL=jdbc:hsqldb:hsql://localhost:9002/mydb
```

Or create `alchemyServer/src/main/resources/application-production.properties`:

```properties
server.port=8080
server.address=0.0.0.0
cors.allowed-origins=https://your-frontend.playit.gg
database.url=jdbc:hsqldb:hsql://localhost:9002/mydb
```

## Step 3: Build for Production

### Frontend
```bash
cd Lexicon
npm run build
```

This creates an optimized production build in `Lexicon/build/`

### Backend - lexiconServer
```bash
cd lexiconServer
./gradlew bootJar
```

Creates JAR at: `lexiconServer/build/libs/lexiconServer-1.0.0.jar`

### Backend - alchemyServer
```bash
cd alchemyServer
./gradlew bootJar
```

Creates JAR at: `alchemyServer/build/libs/alchemyServer-1.0.jar`

## Step 4: Start Database

```bash
# Start HSQLDB server (if not running)
cd /path/to/hsqldb
java -cp hsqldb.jar org.hsqldb.server.Server --database.0 file:mydb --dbname.0 mydb
```

## Step 5: Run Production Servers

### Option A: Using JAR files (recommended)

```bash
# Terminal 1: Start alchemyServer
cd alchemyServer
export CORS_ALLOWED_ORIGINS=https://your-frontend.playit.gg
java -jar build/libs/alchemyServer-1.0.jar --spring.profiles.active=production

# Terminal 2: Start lexiconServer
cd lexiconServer
export CORS_ALLOWED_ORIGINS=https://your-frontend.playit.gg
java -jar build/libs/lexiconServer-1.0.0.jar --spring.profiles.active=production

# Terminal 3: Serve frontend (using serve or similar)
cd Lexicon
npx serve -s build -l 3000
```

### Option B: Development mode with production config

```bash
# Terminal 1: alchemyServer
cd alchemyServer
export CORS_ALLOWED_ORIGINS=https://your-frontend.playit.gg
./gradlew bootRun --args='--spring.profiles.active=production'

# Terminal 2: lexiconServer  
cd lexiconServer
export CORS_ALLOWED_ORIGINS=https://your-frontend.playit.gg
./gradlew bootRun --args='--spring.profiles.active=production'

# Terminal 3: React app
cd Lexicon
npm start
```

## Step 6: Start playit.gg Tunnels

```bash
# Terminal 4: Frontend tunnel
playit tunnel tcp 3000

# Terminal 5: Alchemy tunnel
playit tunnel tcp 8080

# Terminal 6: Lexicon tunnel
playit tunnel tcp 36568
```

## Step 7: Access Your Application

Navigate to your frontend tunnel URL:
```
https://your-frontend.playit.gg
```

## Troubleshooting

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
