# Full Lexicon - Unified Gaming & Media Platform

A comprehensive platform combining the Alchemy game with Lexicon media sharing, using unified user authentication and a gateway architecture.

## Project Structure

```
full_lexicon/
├── alchemyServer/          # Original Alchemy game backend
├── lexiconServer/          # New Lexicon media sharing backend  
├── gateway/                # API gateway for unified access
├── start-dev.sh           # Development startup script
├── stop-all.sh            # Stop all services script
├── test-api.sh            # Complete API testing script
├── test-services.sh       # Service health check script
├── test-direct-vs-gateway.sh # Gateway vs direct access testing
└── README.md              # This file
```

## Architecture Overview

```
                            FRONTEND
                         [React App - :3000]
                                 |
                            HTTP Requests
                                 |
                                 ▼
                       ┌─────────────────────┐
                       │      GATEWAY        │
                       │   (Spring Boot)     │
                       │    Port: 8080       │
                       └─────────────────────┘
                                 │
                    ┌────────────┴────────────┐
                    ▼                         ▼
          ┌─────────────────┐       ┌─────────────────┐
          │    ALCHEMY      │       │     LEXICON     │
          │  (Game Logic)   │       │ (Media Sharing) │
          │  Port: 36567    │       │  Port: 36568    │
          └─────────────────┘       └─────────────────┘
                    │                         │
                    └─────────┬───────────────┘
                              ▼
                    ┌─────────────────────┐
                    │     HSQLDB          │
                    │  (Shared Database)  │
                    │    Port: 9002       │
                    └─────────────────────┘
```

### Services
- **Database (HSQLDB)**: Port 9002 - Shared database for unified users
- **Alchemy Server**: Port 36567 - Game logic and APIs
- **Lexicon Server**: Port 36568 - Media upload/sharing APIs
- **Gateway**: Port 8080 - Unified API access point

### API Routes
- **Alchemy APIs**: `http://localhost:8080/api/alchemy/*` → `http://localhost:36567/api/*`
- **Lexicon APIs**: `http://localhost:8080/api/lexicon/*` → `http://localhost:36568/api/*`

### Data Flow
1. **Frontend** sends requests to Gateway on port 8080
2. **Gateway** routes requests to appropriate backend service
3. **Backend Services** process requests and interact with shared database
4. **Database** maintains unified user accounts and service-specific data

## Features

### Alchemy (Game)
- Player management with inventory and knowledge books
- Potion crafting system
- Game progression and levels

### Lexicon (Media Sharing)
- Audio and video file upload
- Public/private media sharing
- Media streaming and download
- Search functionality
- User-specific media libraries

### Unified System
- **Shared Authentication**: Single user account works for both services
- **Unified Player Object**: Same user data across both platforms
- **Gateway Routing**: Single entry point for all APIs

## Development Scripts

The project includes several utility scripts for development and testing:

### Core Scripts
- **`start-dev.sh`** - Start all services (database, Alchemy, Lexicon, Gateway)
- **`stop-all.sh`** - Stop all running services

### Testing Scripts  
- **`test-services.sh`** - Quick health check of all services
- **`test-api.sh`** - Comprehensive API functionality test
- **`test-direct-vs-gateway.sh`** - Compare direct vs gateway access

### Usage Examples
```bash
# Start development environment
./start-dev.sh

# Test everything is working
./test-services.sh
./test-api.sh

# Clean shutdown
./stop-all.sh
```

## Quick Start

### Development Setup

1. **Start all services**:
   ```bash
   ./start-dev.sh
   ```

2. **Test the setup**:
   ```bash
   # Check gateway health
   curl http://localhost:8080/api/gateway/health
   
   # Check alchemy service
   curl http://localhost:8080/api/alchemy/health
   
   # Check lexicon service  
   curl http://localhost:8080/api/lexicon/health
   ```

### API Examples

#### User Registration (works for both services)
```bash
curl -X POST http://localhost:8080/api/lexicon/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "password123",
    "email": "test@example.com",
    "displayName": "Test User"
  }'
```

#### Upload Media File
```bash
curl -X POST http://localhost:8080/api/lexicon/media/upload \
  -F "file=@/path/to/your/video.mp4" \
  -F "userId=1" \
  -F "title=My Video" \
  -F "description=A test video" \
  -F "isPublic=true"
```

#### Get Public Media
```bash
curl http://localhost:8080/api/lexicon/media/public
```

#### Stream Media File
```bash
curl http://localhost:8080/api/lexicon/media/1/stream
```

## Development Notes

### Database Schema

The unified system uses a shared HSQLDB with:

**Players Table** (Enhanced):
- `id`, `username`, `password`, `level` (original Alchemy fields)
- `email`, `display_name`, `registration_date`, `last_login_date` (new unified fields)

**Media Files Table** (New):
- File metadata and storage information
- User ownership and privacy settings
- Upload timestamps and file details

### File Storage

Media files are stored locally in `lexiconServer/uploads/` directory with:
- UUID-based filenames to prevent conflicts
- Original filename preservation in database
- Content-type detection for proper streaming

### CORS Configuration

All services are configured to allow requests from `http://localhost:3000` for React frontend development.

## Production Deployment

For production deployment:

1. Replace playit tunnels with proper reverse proxy (nginx)
2. Use external database (PostgreSQL/MySQL)
3. Configure proper file storage (cloud storage)
4. Set up SSL certificates
5. Configure environment-specific settings

## Troubleshooting

### Port Conflicts
If you get port conflicts, check what's running:
```bash
lsof -i :8080  # Gateway
lsof -i :36567 # Alchemy  
lsof -i :36568 # Lexicon
lsof -i :9002  # Database
```

### Database Issues
- Ensure HSQLDB server starts first
- Check `alchemyServer/alchemydb.*` files exist
- Verify database connection in logs

### File Upload Issues  
- Check `lexiconServer/uploads/` directory permissions
- Verify file size limits in `application.properties`
- Check available disk space

## Technology Stack

- **Backend**: Spring Boot 3.1.4, Java 17
- **Database**: HSQLDB (embedded)
- **Gateway**: Spring Boot with WebFlux
- **Security**: Spring Security with BCrypt
- **File Handling**: Multipart file upload with local storage
