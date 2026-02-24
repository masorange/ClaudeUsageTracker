# PhotoVault - Multimedia Manager Design

**Date**: 2026-02-24
**Status**: Approved

## Overview

Cross-platform desktop application (macOS + Windows) for managing a personal photo/video collection stored on a backup drive. Native standalone app (.app/.exe) with fast performance for 100k+ items.

## Requirements

- Browse photos/videos in existing folder structure
- Edit EXIF/IPTC/XMP metadata directly in files (caption, tags, GPS, rating, date)
- Full-text search across all metadata
- Interactive map with geolocated photos (online tiles via OpenStreetMap)
- Local AI face recognition with automatic background scanning, grouping, and manual review
- Virtual albums (references only, no file duplication)
- Similar image grouping via perceptual hashing
- Basic editing: rotate and crop (destructive, overwrites original)
- Videos: basic support (playback + metadata editing)

## Tech Stack: Tauri 2 + Rust + React

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Framework | Tauri 2 | Cross-platform desktop app, IPC, bundling, auto-update |
| Backend | Rust | File scanning, metadata R/W, AI inference, image processing |
| Frontend | React + TypeScript | UI: grids, map, editors, search |
| Database | SQLite (rusqlite, WAL mode) | Local index/cache, FTS5 search, face embeddings |
| Metadata | rexiv2 + exiftool (fallback) | Read/write EXIF/IPTC/XMP in files |
| Face AI | ONNX Runtime (ort crate) | InsightFace (detection) + ArcFace (embedding) |
| Image | image crate | Thumbnails, rotate, crop |
| Similar | img_hash crate | Perceptual hashing (pHash) |
| Map | Leaflet + react-leaflet | Interactive map with clustered markers |
| UI Grid | react-virtuoso | Virtualized grid for 100k+ thumbnails |
| State | zustand + @tanstack/react-query | Frontend state and async data cache |

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Tauri 2 App                          │
│                                                         │
│  ┌─────────────────────────────────────────────────┐    │
│  │              React / TypeScript UI               │    │
│  │  Explorer | Viewer | Map | Faces | Albums |     │    │
│  │  Search | Similar                                │    │
│  └──────────────────┬──────────────────────────────┘    │
│                     │ Tauri IPC (commands + events)      │
│  ┌──────────────────┴──────────────────────────────┐    │
│  │              Rust Backend                        │    │
│  │  File Scanner | Metadata Engine | Face AI       │    │
│  │  Image Processing | SQLite Manager | pHash      │    │
│  └─────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────┘
```

Communication: Tauri IPC commands (frontend -> backend) and events (backend -> frontend for progress). Heavy operations run in dedicated Rust threads via `tokio::spawn_blocking`.

## Data Model (SQLite)

### media_items
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| file_path | TEXT UNIQUE | Absolute path to file |
| file_name | TEXT | Filename |
| file_size | INTEGER | Bytes |
| file_hash | TEXT | SHA-256 for change detection |
| media_type | TEXT | 'photo' or 'video' |
| mime_type | TEXT | e.g. 'image/jpeg' |
| width | INTEGER | Pixels |
| height | INTEGER | Pixels |
| date_taken | DATETIME | From EXIF DateTimeOriginal |
| date_modified | DATETIME | File modification time |
| date_indexed | DATETIME | When indexed by app |
| latitude | REAL | GPS latitude |
| longitude | REAL | GPS longitude |
| caption | TEXT | IPTC/XMP caption |
| rating | INTEGER | 0-5 stars |
| perceptual_hash | TEXT | pHash for similar detection |
| thumbnail_path | TEXT | Path to cached thumbnail |
| needs_rescan | BOOLEAN | Flag for re-indexing |

### tags + media_tags (N:M)
Tags for categorization and search. Many-to-many with media_items.

### albums + album_items (N:M)
Virtual albums. `album_items` contains only references (media_id + sort_order). No files are copied.

### faces
| Column | Type | Description |
|--------|------|-------------|
| id | INTEGER PK | Auto-increment |
| media_id | FK | Reference to media_items |
| bbox_x/y/w/h | REAL | Bounding box (normalized 0-1) |
| embedding | BLOB | 512-dim ArcFace vector |
| person_id | FK | Reference to persons (nullable) |
| confidence | REAL | Detection confidence |

### persons
Named people. Each has a representative face and a name assigned by user.

### similar_groups + similar_group_items
Groups of perceptually similar images with similarity scores.

### Key Indexes
- `media_items(file_path)` - path lookup
- `media_items(date_taken)` - temporal sorting
- `media_items(latitude, longitude)` - geo queries
- FTS5 on caption + tags - full-text search
- `faces(person_id)` - person photo listing
- `media_items(perceptual_hash)` - similar lookup

## Backend Modules (Rust)

### File Scanner
- `walkdir` for recursive traversal
- Supported: jpg, jpeg, png, tiff, heic, webp, raw, mp4, mov, avi, mkv
- Compares file_hash with SQLite to detect new/modified files
- Reports progress via Tauri events: `scan:progress { total, processed, current_file }`
- Runs in dedicated thread

### Metadata Engine
- Read/Write: `rexiv2` (libexiv2 bindings) for EXIF/IPTC/XMP
- Fallback: `exiftool` subprocess for rare formats and video
- Editable fields: caption, tags, rating, GPS, date_taken
- Syncs writes to both file and SQLite

### Face AI Engine
- Models: InsightFace (detection) + ArcFace (embedding) in ONNX format
- Runtime: `ort` crate (onnxruntime-rs), supports CPU + GPU (CoreML macOS, DirectML Windows)
- Pipeline: detect faces -> align/crop -> generate 512-dim embedding -> cosine compare -> assign/cluster
- Threshold: cosine similarity > 0.6 -> same person
- Auto-scanning in background, newest photos first
- Manual review: merge clusters, split incorrect assignments

### Image Processing
- `image` crate for decode/encode
- Thumbnails: 300px in `~/.photoapp/thumbnails/` named by file hash
- Rotate: lossless for JPEG via EXIF orientation or jpegtran
- Crop: destructive, overwrites original

### Similar Image Hasher
- `img_hash` crate for perceptual hashing
- Calculated during initial scan
- Grouping: Hamming distance < 10 threshold
- User reviews groups to confirm/dismiss

### SQLite Manager
- `rusqlite` with WAL mode for concurrent reads
- FTS5 for full-text search
- Versioned migrations embedded in binary
- Connection pool via `r2d2`

## UI Views (React)

### Layout
Sidebar (folders, albums, persons, search, map, similar) + Main content area + Status bar with background task progress.

### Views
- **Explorer (Grid)**: Virtualized thumbnail grid (react-virtuoso). Infinite scroll. Multi-select. Sort by date/name/rating.
- **Viewer**: Full-screen single photo. Arrow key navigation. Right panel with editable metadata. Rotate/crop tools.
- **Map**: Leaflet interactive map with clustered markers. Click cluster -> photo grid. Click marker -> open photo.
- **Faces**: Person grid. Click person -> their photo grid. Merge/split person controls.
- **Albums**: Album grid with covers. Create, drag-to-add, reorder.
- **Search**: Search bar with filters: text (caption/tags), date range, person, rating, has/no GPS.
- **Similar**: Groups of similar images for review.

## Key Data Flows

### First Scan
User selects root folder -> Rust walkdir -> read metadata + generate thumbnail + compute pHash per file -> insert SQLite -> report progress -> launch face scanning.

### Metadata Edit
User edits in Viewer -> Tauri command -> Rust writes to file via rexiv2 -> updates SQLite -> confirms to frontend -> react-query invalidation.

### Face Recognition (Background)
App start -> worker thread picks unscanned images (newest first) -> detect faces -> generate embeddings -> compare with existing -> assign or create cluster -> save to SQLite -> emit progress events.

### Search
User types query -> Tauri command -> SQL with FTS5 + WHERE filters -> return media_ids -> frontend renders virtualized grid.

### Virtual Album
Create album -> INSERT albums. Drag photos -> INSERT album_items (reference only). Open album -> JOIN query -> render grid.

## Error Handling

- **Disconnected drive**: Show warning, allow browsing cached data (thumbnails + SQLite). Block edits.
- **Corrupt file**: Mark with error in SQLite, skip. Show error icon in UI.
- **Metadata write failure**: Show error to user. Don't update SQLite (maintain consistency). Offer retry.
- **External modification**: Detect via hash change on rescan, re-index automatically.
- **Face merge undo**: `faces` table preserves assignment history, allowing undo of person merges.

## Distribution

- **macOS**: `.dmg` bundle via Tauri. Includes exiftool and ONNX models.
- **Windows**: `.msi` installer via Tauri.
- **AI Models**: Downloaded on first use (~150MB total). Stored in `~/.photoapp/models/`. Progress bar during download.
- **Auto-update**: Tauri built-in updater with signature verification.
- **Local data**: All in `~/.photoapp/` (thumbnails, SQLite DB, models, config).
