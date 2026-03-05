# Lexicon Storage Architecture

## Current Storage Issues
- Files stored in database (HSQLDB) - inefficient for large files
- No file organization by type/size
- No progress bars for large uploads
- Potential lag for video streaming from database

## Optimized Storage Solution

### 1. File System Storage Structure
```
/media/alexpdyak32/7db05fe3-9f6a-46cb-82dd-8ff00d8488a0/lexicon-storage/
├── audiobooks/
│   ├── large/          # > 100MB audiobooks
│   └── standard/       # < 100MB audiobooks  
├── music/
│   ├── lossless/       # FLAC, high-quality files
│   └── compressed/     # MP3, AAC files
├── videos/
│   ├── original/       # Original uploaded videos
│   ├── transcoded/     # Optimized for streaming
│   └── thumbnails/     # Video preview thumbnails
├── temp/
│   ├── chunks/         # Chunked upload temporary storage
│   ├── processing/     # Files being processed/transcoded
│   └── cache/          # Streaming cache for frequently accessed files
└── backups/           # Automated backup storage
```

### 2. Storage Optimization Strategy

#### Small Files (< 10MB)
- Store in database for fast access
- Suitable for: Short music tracks, documents, images

#### Medium Files (10MB - 100MB) 
- Store on file system with database metadata
- Suitable for: Most music, small videos, compressed audiobooks

#### Large Files (> 100MB)
- Store on file system with streaming optimization
- Generate thumbnails/previews for videos
- Use HTTP range requests for efficient streaming
- Suitable for: Audiobooks, long videos, high-quality music

### 3. Video Streaming Optimization

#### Transcoding Pipeline
1. **Original Upload** → Store original in `videos/original/`
2. **Background Processing** → Create optimized versions in `videos/transcoded/`
3. **Thumbnail Generation** → Create preview images in `videos/thumbnails/`
4. **Adaptive Streaming** → Multiple quality levels for different bandwidth

#### Streaming Features
- **HTTP Range Requests** for seeking in large files
- **Progressive Download** for immediate playback start
- **Adaptive Bitrate** based on connection speed
- **Chunk Caching** for frequently accessed content

### 4. Upload Progress Enhancement

#### Frontend Improvements
- **Real-time Progress Bars** with percentage and speed
- **ETA Calculation** based on upload speed
- **Pause/Resume** capability for large uploads
- **Background Uploads** that continue even if page is closed
- **Thumbnail Preview** during video upload processing

#### Backend Improvements
- **WebSocket Progress Updates** for real-time feedback
- **Resumable Uploads** with chunk verification
- **Parallel Processing** for multiple file uploads
- **Storage Space Monitoring** and warnings

### 5. Performance Benefits

#### File System vs Database Storage
- **50-90% faster** file access for large files
- **Reduced database size** and better query performance
- **Better backup/restore** capabilities
- **Easier file management** and organization

#### Video Streaming Improvements
- **Instant playback start** with progressive download
- **No buffering delays** for seeking in files
- **Multiple quality options** for different devices
- **Thumbnail previews** for quick navigation

### 6. Implementation Plan

#### Phase 1: File System Migration
1. Create storage directory structure on 500GB volume
2. Add configuration for storage paths
3. Implement file system storage methods
4. Migration script for existing database files

#### Phase 2: Enhanced Upload Experience  
1. Add WebSocket progress updates
2. Implement resumable upload capability
3. Add upload speed and ETA display
4. Background upload processing

#### Phase 3: Video Streaming Optimization
1. Implement HTTP range request support
2. Add video transcoding pipeline
3. Generate video thumbnails
4. Adaptive quality streaming

#### Phase 4: Advanced Features
1. Automatic file organization
2. Storage usage analytics
3. Automated cleanup of old temp files
4. Performance monitoring and alerts

### 7. Configuration Changes Needed

#### Storage Paths
```properties
lexicon.storage.base.path=/media/alexpdyak32/7db05fe3-9f6a-46cb-82dd-8ff00d8488a0/lexicon-storage
lexicon.storage.temp.path=${lexicon.storage.base.path}/temp
lexicon.storage.audiobooks.path=${lexicon.storage.base.path}/audiobooks
lexicon.storage.music.path=${lexicon.storage.base.path}/music  
lexicon.storage.videos.path=${lexicon.storage.base.path}/videos
lexicon.storage.threshold.small=10485760     # 10MB
lexicon.storage.threshold.large=104857600    # 100MB
```

#### Performance Settings
```properties
lexicon.upload.chunk.size=10485760           # 10MB chunks
lexicon.streaming.buffer.size=1048576        # 1MB buffer
lexicon.transcoding.parallel.jobs=2          # CPU cores for video processing
lexicon.cache.size=536870912                 # 512MB cache
```

This architecture will provide:
- **Faster file access** (especially for large files)
- **Better organization** and management
- **Improved streaming performance** 
- **Enhanced user experience** with progress tracking
- **Scalability** for future growth
- **Efficient use** of your 500GB storage volume