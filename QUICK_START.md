# Production Quick Start Guide

## 🚀 Quick Setup (5 minutes)

### 1. Get your playit.gg tunnel URLs
```bash
# Start three tunnels (in separate terminals)
playit tunnel tcp 3000   # Frontend - note the URL
playit tunnel tcp 8080   # Alchemy - note the URL  
playit tunnel tcp 36568  # Lexicon - note the URL
```

### 2. Configure frontend
Create `Lexicon/.env.production.local`:
```bash
REACT_APP_API_URL=https://your-alchemy.playit.gg
REACT_APP_LEXICON_API_URL=https://your-lexicon.playit.gg
REACT_APP_FRONTEND_URL=https://your-frontend.playit.gg
REACT_APP_ENV=production
```

### 3. Set CORS and start servers
```bash
# Set CORS to your frontend URL
export CORS_ALLOWED_ORIGINS=https://your-frontend.playit.gg

# Start everything
./start-production.sh
```

### 4. Access your app
Navigate to: `https://your-frontend.playit.gg`

## 🛑 Stop Services
```bash
./stop-production.sh
```

## 📊 Check Status
```bash
# View logs
tail -f logs/frontend.log
tail -f logs/alchemy.log
tail -f logs/lexicon.log
tail -f logs/database.log

# Check health
curl http://localhost:8080/api/health
curl http://localhost:36568/api/health
```

## 🔧 Development vs Production

| Environment | Command | Uses |
|-------------|---------|------|
| Development | `npm start` | localhost URLs, hot reload |
| Production | `./start-production.sh` | playit.gg URLs, optimized build |

## 📝 Environment Variables Cheat Sheet

### Must Change for Production:
- `REACT_APP_API_URL` → Your alchemy playit.gg URL
- `REACT_APP_LEXICON_API_URL` → Your lexicon playit.gg URL
- `REACT_APP_FRONTEND_URL` → Your frontend playit.gg URL
- `CORS_ALLOWED_ORIGINS` → Your frontend playit.gg URL

### Can Keep Defaults:
- Ports (3000, 8080, 36568, 9002)
- DATABASE_URL (if using localhost HSQLDB)
- UPLOAD_DIR (./uploads)

## ⚠️ Common Issues

**CORS Error?**
- Check CORS_ALLOWED_ORIGINS matches your frontend URL exactly
- No trailing slashes!
- Restart servers after changing

**Can't access?**
- Verify all playit.gg tunnels are running
- Check firewall isn't blocking ports
- Verify servers started successfully (check logs/)

**Login not working?**
- Clear browser cookies
- Check database is running
- Verify alchemy server is accessible

## 🔐 Security Checklist

- [ ] All 3 playit.gg tunnels configured
- [ ] CORS_ALLOWED_ORIGINS set correctly
- [ ] Frontend built with production config
- [ ] Database password changed from default
- [ ] Uploaded files directory secured
- [ ] Logs directory created

## 📦 Ports Reference

| Service | Port | Protocol | Public? |
|---------|------|----------|---------|
| Frontend | 3000 | HTTP | ✅ via playit.gg |
| Alchemy | 8080 | HTTP | ✅ via playit.gg |
| Lexicon | 36568 | HTTP | ✅ via playit.gg |
| Database | 9002 | HSQLDB | ❌ localhost only |

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
