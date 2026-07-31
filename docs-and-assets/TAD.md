# Lecto — Technical Architecture Document (TAD)

| Field            | Value                                    |
| ---------------- | ---------------------------------------- |
| **Document**     | Technical Architecture Document (TAD)    |
| **Product**      | Lecto                                    |
| **Version**      | 1.0.0                                    |
| **Status**       | Draft                                    |
| **Date**         | 2026-07-07                               |
| **Classification** | Internal — Engineering                 |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [System Architecture Overview](#2-system-architecture-overview)
3. [Mobile App Architecture](#3-mobile-app-architecture)
4. [Backend Architecture](#4-backend-architecture)
5. [Data Architecture](#5-data-architecture)
6. [Processing Pipeline](#6-processing-pipeline)
7. [Offline-First Architecture](#7-offline-first-architecture)
8. [Exception Handling Matrix](#8-exception-handling-matrix)
9. [Scalability Considerations](#9-scalability-considerations)
10. [Monitoring & Observability](#10-monitoring--observability)
11. [Security Architecture](#11-security-architecture)
12. [Appendices](#12-appendices)

---

## 1. Executive Summary

**Lecto** is a cross-platform mobile application that enables students to record lectures, automatically generate speech-to-text transcripts, and produce AI-powered structured study notes and exportable PDFs. The system is designed with an **offline-first** architecture: students can record lectures with zero connectivity and the app will intelligently queue, sync, and process content when a network becomes available.

### 1.1 Core User Journey

```
Record Lecture → Chunk Audio → Upload → Transcribe → Assemble Transcript → AI Summary → PDF Export
```

### 1.2 Key Architectural Principles

| Principle                | Rationale                                                                                     |
| ------------------------ | --------------------------------------------------------------------------------------------- |
| **Offline-first**        | Students record in lecture halls with poor connectivity; data must never be lost              |
| **Chunk-based pipeline** | Long recordings (60-120 min) are split into 10-20 min chunks for resilient parallel processing |
| **Idempotent processing**| Every pipeline stage can be retried safely without duplication                                |
| **Audio is ephemeral**   | Audio chunks are deleted after a confirmed transcript to minimise storage costs               |
| **Graceful degradation** | If the AI API is down, transcripts still work; if STT is down, audio is preserved            |

### 1.3 Technology Stack Summary

| Layer               | Technology                                      | Purpose                                  |
| -------------------- | ----------------------------------------------- | ---------------------------------------- |
| Mobile App           | Flutter 3.x / Dart                              | Cross-platform iOS + Android             |
| Backend API          | Node.js 20 LTS + Fastify                        | REST API, job orchestration              |
| Primary Database     | PostgreSQL 16                                   | Persistent relational data               |
| Local Database       | SQLite (via `sqflite` / `drift`)                 | On-device offline storage                |
| Cloud Storage        | Google Cloud Storage (GCS)                       | Audio chunk and PDF blob storage         |
| Speech-to-Text       | Google Cloud Speech-to-Text (primary)            | Audio → transcript                       |
| STT Fallback         | OpenAI Whisper API                               | Fallback transcription                   |
| AI Processing        | Google Gemini API                                | Transcript → structured study notes      |
| PDF Generation       | Puppeteer (server-side)                          | Markdown/HTML → branded PDF              |
| Authentication       | Firebase Auth                                    | Email/password, Google, Apple sign-in    |
| Push Notifications   | Firebase Cloud Messaging (FCM)                   | Processing status alerts                 |
| Infrastructure       | Docker → Google Cloud Run                        | Serverless container hosting             |
| Task Queue           | Google Cloud Tasks / BullMQ + Redis              | Background job processing                |
| CDN                  | Cloud CDN (via GCS)                              | Static asset and PDF delivery            |

---

## 2. System Architecture Overview

### 2.1 High-Level Architecture Diagram

```mermaid
graph TB
    subgraph "Client Layer"
        MA["📱 Flutter Mobile App<br/>(iOS + Android)"]
        MA_DB["🗄️ SQLite<br/>(Local DB)"]
        MA_FS["📁 Local File System<br/>(Audio Chunks)"]
    end

    subgraph "Edge / CDN"
        CDN["🌐 Cloud CDN"]
    end

    subgraph "API Layer"
        LB["⚖️ Cloud Load Balancer"]
        API1["🖥️ API Instance 1<br/>(Cloud Run)"]
        API2["🖥️ API Instance 2<br/>(Cloud Run)"]
        APIn["🖥️ API Instance N<br/>(Cloud Run)"]
    end

    subgraph "Authentication"
        AUTH["🔐 Firebase Auth"]
    end

    subgraph "Message / Queue Layer"
        QUEUE["📨 Cloud Tasks<br/>+ BullMQ / Redis"]
    end

    subgraph "Processing Workers"
        W_STT["🎤 STT Worker<br/>(Cloud Run Job)"]
        W_AI["🤖 AI Worker<br/>(Cloud Run Job)"]
        W_PDF["📄 PDF Worker<br/>(Cloud Run Job)"]
    end

    subgraph "External APIs"
        GSTT["Google Cloud<br/>Speech-to-Text"]
        WHISPER["OpenAI<br/>Whisper API"]
        GEMINI["Google<br/>Gemini API"]
    end

    subgraph "Data Layer"
        PG["🐘 PostgreSQL<br/>(Cloud SQL)"]
        GCS["☁️ Google Cloud Storage<br/>(Audio + PDFs)"]
        REDIS["⚡ Redis<br/>(Cache + Queue)"]
    end

    subgraph "Notifications"
        FCM["🔔 Firebase Cloud<br/>Messaging"]
    end

    subgraph "Observability"
        LOG["📊 Cloud Logging"]
        MON["📈 Cloud Monitoring"]
        TRACE["🔍 Cloud Trace"]
    end

    MA <--> MA_DB
    MA <--> MA_FS
    MA -- "HTTPS" --> LB
    MA <--> AUTH
    LB --> API1
    LB --> API2
    LB --> APIn
    API1 & API2 & APIn --> PG
    API1 & API2 & APIn --> GCS
    API1 & API2 & APIn --> REDIS
    API1 & API2 & APIn --> QUEUE
    QUEUE --> W_STT
    QUEUE --> W_AI
    QUEUE --> W_PDF
    W_STT --> GSTT
    W_STT -.-> WHISPER
    W_AI --> GEMINI
    W_PDF --> GCS
    W_STT & W_AI & W_PDF --> PG
    API1 & API2 & APIn --> FCM
    CDN --> GCS
    API1 & API2 & APIn --> LOG
    API1 & API2 & APIn --> MON
    API1 & API2 & APIn --> TRACE
```

### 2.2 Component Interaction Diagram

```mermaid
sequenceDiagram
    participant U as Student
    participant App as Flutter App
    participant DB as SQLite (Local)
    participant FS as Local FileSystem
    participant API as Backend API
    participant Q as Task Queue
    participant GCS as Cloud Storage
    participant STT as STT Worker
    participant AI as AI Worker
    participant PDF as PDF Worker
    participant FCM as Push Notification

    U->>App: Start Recording
    App->>FS: Write audio stream
    App->>DB: Create recording record (status: recording)

    loop Every 10-20 minutes
        App->>FS: Finalize chunk N, start chunk N+1
        App->>DB: Create chunk record (status: pending_upload)
    end

    U->>App: Stop Recording
    App->>FS: Finalize last chunk
    App->>DB: Update recording (status: pending_sync)

    alt Online
        loop For each pending chunk
            App->>API: POST /chunks (upload audio)
            API->>GCS: Store audio blob
            API-->>App: 200 OK (chunk_id)
            App->>DB: Update chunk (status: uploaded)
        end
        App->>API: POST /recordings/:id/process
        API->>Q: Enqueue STT jobs for all chunks
        Q->>STT: Process chunk
        STT->>GCS: Read audio
        STT-->>Q: Transcript text
        STT->>API: PATCH /chunks/:id (transcript)
        API->>Q: Enqueue Assembly job
        API->>Q: Enqueue AI summary job
        Q->>AI: Generate structured notes
        AI-->>API: Summary markdown
        API->>Q: Enqueue PDF job
        Q->>PDF: Render PDF
        PDF->>GCS: Upload PDF
        API->>FCM: Notify "Notes ready!"
        FCM-->>App: Push notification
        App->>API: GET /recordings/:id
        App->>DB: Sync updated data
    else Offline
        App->>DB: Queue all chunks for later sync
        Note over App,DB: Sync engine retries when connectivity returns
    end
```

### 2.3 End-to-End Data Flow Diagram

```mermaid
flowchart LR
    subgraph "1 — Capture"
        MIC["🎙️ Microphone"] --> PCM["PCM Audio Stream"]
        PCM --> ENCODE["AAC/Opus Encoder"]
        ENCODE --> CHUNK["Chunk Splitter<br/>(10-20 min)"]
        CHUNK --> LOCAL["Local .m4a Files"]
    end

    subgraph "2 — Transport"
        LOCAL --> SYNC["Sync Engine"]
        SYNC --> UPLOAD["Multipart Upload<br/>to GCS via API"]
    end

    subgraph "3 — Transcription"
        UPLOAD --> STT_Q["STT Job Queue"]
        STT_Q --> GSTT["Google STT API"]
        GSTT --> RAW_T["Raw Chunk<br/>Transcript"]
        STT_Q -.-> WHISPER["Whisper API<br/>(fallback)"]
        WHISPER -.-> RAW_T
    end

    subgraph "4 — Assembly"
        RAW_T --> ASSEMBLE["Transcript<br/>Assembler"]
        ASSEMBLE --> MAIN_MD["main.md<br/>(Full Transcript)"]
    end

    subgraph "5 — AI Processing"
        MAIN_MD --> GEMINI["Gemini API"]
        GEMINI --> NOTES["Structured<br/>Study Notes"]
    end

    subgraph "6 — Export"
        NOTES --> PDF_GEN["Puppeteer<br/>PDF Renderer"]
        PDF_GEN --> PDF_FILE["📄 Final PDF"]
        PDF_FILE --> GCS_PDF["GCS Bucket"]
        GCS_PDF --> CDN_PDF["CDN URL"]
    end

    subgraph "7 — Cleanup"
        RAW_T -- "Transcript confirmed" --> DEL["🗑️ Delete Audio<br/>from GCS"]
    end
```

---

## 3. Mobile App Architecture

### 3.1 Architecture Pattern — Clean Architecture with BLoC

The Flutter app follows **Clean Architecture** layered into three rings, with the **BLoC (Business Logic Component)** pattern for state management.

```mermaid
graph TB
    subgraph "Presentation Layer"
        PAGES["Pages / Screens"]
        WIDGETS["Widgets"]
        BLOCS["BLoC / Cubits"]
    end

    subgraph "Domain Layer"
        UC["Use Cases"]
        ENTITIES["Entities"]
        REPO_IF["Repository Interfaces<br/>(abstract)"]
    end

    subgraph "Data Layer"
        REPO_IMPL["Repository Implementations"]
        DS_REMOTE["Remote Data Source<br/>(API Client)"]
        DS_LOCAL["Local Data Source<br/>(SQLite via Drift)"]
        DS_FILE["File Data Source<br/>(Audio Files)"]
        MODELS["Data Models / DTOs"]
    end

    PAGES --> BLOCS
    WIDGETS --> BLOCS
    BLOCS --> UC
    UC --> REPO_IF
    REPO_IF -.-> REPO_IMPL
    REPO_IMPL --> DS_REMOTE
    REPO_IMPL --> DS_LOCAL
    REPO_IMPL --> DS_FILE
    DS_REMOTE --> MODELS
    DS_LOCAL --> MODELS
```

### 3.2 Flutter Project Structure

```
mobile-app/
├── lib/
│   ├── main.dart
│   ├── app.dart                         # MaterialApp, routing, DI
│   ├── injection_container.dart          # GetIt / Injectable setup
│   │
│   ├── core/
│   │   ├── constants/                   # API URLs, chunk duration, thresholds
│   │   ├── errors/                      # Failure classes, exceptions
│   │   ├── network/                     # Connectivity checker, Dio client
│   │   ├── theme/                       # App theme, typography
│   │   ├── utils/                       # Date formatters, file helpers
│   │   └── services/
│   │       ├── connectivity_service.dart
│   │       ├── notification_service.dart
│   │       └── storage_monitor_service.dart
│   │
│   ├── features/
│   │   ├── auth/
│   │   │   ├── data/
│   │   │   │   ├── datasources/
│   │   │   │   ├── models/
│   │   │   │   └── repositories/
│   │   │   ├── domain/
│   │   │   │   ├── entities/
│   │   │   │   ├── repositories/
│   │   │   │   └── usecases/
│   │   │   └── presentation/
│   │   │       ├── bloc/
│   │   │       ├── pages/
│   │   │       └── widgets/
│   │   │
│   │   ├── recording/
│   │   │   ├── data/
│   │   │   │   ├── datasources/
│   │   │   │   │   ├── audio_recorder_datasource.dart
│   │   │   │   │   ├── recording_local_datasource.dart
│   │   │   │   │   └── recording_remote_datasource.dart
│   │   │   │   ├── models/
│   │   │   │   └── repositories/
│   │   │   ├── domain/
│   │   │   │   ├── entities/
│   │   │   │   │   ├── recording.dart
│   │   │   │   │   └── audio_chunk.dart
│   │   │   │   ├── repositories/
│   │   │   │   └── usecases/
│   │   │   │       ├── start_recording.dart
│   │   │   │       ├── stop_recording.dart
│   │   │   │       ├── pause_recording.dart
│   │   │   │       └── configure_chunk_duration.dart
│   │   │   └── presentation/
│   │   │       ├── bloc/
│   │   │       │   ├── recording_bloc.dart
│   │   │       │   ├── recording_event.dart
│   │   │       │   └── recording_state.dart
│   │   │       ├── pages/
│   │   │       └── widgets/
│   │   │
│   │   ├── subjects/                    # Subject/course management
│   │   ├── transcripts/                 # Transcript display + editing
│   │   ├── summaries/                   # AI-generated study notes
│   │   ├── sync/                        # Sync engine UI + status
│   │   └── settings/                    # User preferences
│   │
│   └── services/
│       ├── audio/
│       │   ├── audio_recording_service.dart
│       │   ├── audio_chunk_manager.dart
│       │   └── audio_codec_service.dart
│       ├── sync/
│       │   ├── sync_engine.dart
│       │   ├── sync_queue.dart
│       │   └── conflict_resolver.dart
│       └── background/
│           ├── background_recording_service.dart
│           └── background_upload_service.dart
│
├── test/
├── integration_test/
├── android/
├── ios/
└── pubspec.yaml
```

### 3.3 Audio Recording Service Architecture

```mermaid
stateDiagram-v2
    [*] --> Idle
    Idle --> Initializing: startRecording()
    Initializing --> Recording: Mic acquired
    Initializing --> Error: Permission denied
    Recording --> Chunking: chunkInterval elapsed
    Chunking --> Recording: New chunk started
    Recording --> Paused: pauseRecording()
    Paused --> Recording: resumeRecording()
    Recording --> Finalizing: stopRecording()
    Paused --> Finalizing: stopRecording()
    Finalizing --> Idle: Chunks saved to disk
    Error --> Idle: reset()

    note right of Chunking
        1. Finalize current chunk file
        2. Insert chunk record in SQLite
        3. Start new chunk file
        4. No audible gap (< 50ms)
    end note
```

#### 3.3.1 Recording Configuration

```dart
/// Default recording configuration
class RecordingConfig {
  final Duration chunkDuration;       // default: 15 minutes
  final AudioCodec codec;             // default: AAC (.m4a)
  final int sampleRate;               // default: 44100 Hz
  final int bitRate;                  // default: 128 kbps
  final int channels;                 // default: 1 (mono)
  final double storageWarningGB;      // default: 0.5 GB remaining
  final double storageCriticalGB;     // default: 0.2 GB remaining

  // Calculated: ~1 MB per minute at 128kbps mono AAC
  // 15-min chunk ≈ 15 MB
  // 2-hour lecture ≈ 120 MB (8 chunks)
}
```

#### 3.3.2 Chunking Mechanism

```mermaid
sequenceDiagram
    participant Timer as Chunk Timer
    participant ARS as AudioRecordingService
    participant Codec as Audio Codec
    participant FS as File System
    participant DB as SQLite

    Note over Timer: Timer fires every 15 min (configurable)
    Timer->>ARS: onChunkInterval()
    ARS->>Codec: Stop writing to chunk_N.m4a
    ARS->>Codec: Start writing to chunk_N+1.m4a
    Note over Codec: Gap < 50ms (seamless)
    ARS->>FS: Verify chunk_N.m4a integrity (size > 0, valid header)
    FS-->>ARS: File OK (size, checksum)
    ARS->>DB: INSERT chunk (recording_id, index=N, status=pending_upload,<br/>file_path, file_size, checksum_sha256, duration_ms)
    ARS->>ARS: Emit ChunkCreated event
```

**Key design decisions:**

- **Codec**: AAC in `.m4a` container — universally supported, good compression (~1 MB/min at 128 kbps mono), hardware-accelerated encoding on both iOS and Android.
- **Chunk boundary**: Uses the platform audio recorder's ability to stop/start with a new file path. The gap is imperceptible (< 50 ms). Overlap is not needed because STT handles boundaries well.
- **Integrity check**: Each finalised chunk has its SHA-256 checksum computed and stored. This checksum is verified after upload to GCS to guarantee zero-corruption.
- **Configurable duration**: Users can set chunk duration (10, 15, or 20 minutes) in Settings. Shorter chunks = faster first-transcript delivery but more HTTP overhead.

#### 3.3.3 Background Service for Recording

| Platform | Mechanism                                                                                          |
| -------- | -------------------------------------------------------------------------------------------------- |
| **Android** | Foreground Service with persistent notification ("Recording lecture…"). Uses `flutter_foreground_task` or `android_alarm_manager_plus`. Keeps CPU wake lock. |
| **iOS**     | Background audio session (`AVAudioSession.Category.record`). The app registers for background audio mode in `Info.plist`. iOS natively permits indefinite background recording as long as the session is active. |

**App killed mid-recording recovery**: The background service writes a `recording_state.json` marker to the app's documents directory every 30 seconds containing the current recording ID, chunk index, and byte offset. On next app launch, the `RecoveryService` reads this file and either resumes or salvages partial chunks.

### 3.4 Local SQLite Database Schema

> Full schema detailed in [Section 5 — Data Architecture](#5-data-architecture). The local schema mirrors the cloud schema with the following additions:

| Extra Column         | Purpose                                                        |
| -------------------- | -------------------------------------------------------------- |
| `sync_status`        | `enum('synced', 'pending_create', 'pending_update', 'pending_delete', 'conflict')` |
| `local_updated_at`   | Timestamp of last local modification                           |
| `server_updated_at`  | Timestamp from last known server version                       |
| `local_file_path`    | Absolute path to the audio chunk file on device                |
| `upload_progress`    | Float 0.0–1.0 for in-progress uploads                         |

### 3.5 File Management

```mermaid
flowchart TD
    A["Audio Chunk Created"] --> B{"Transcript\nConfirmed?"}
    B -- No --> C["Retain on device"]
    C --> D{"Uploaded to GCS?"}
    D -- Yes --> E["Mark local copy as\n'deletable_after_transcript'"]
    D -- No --> F["Retain — needed for upload"]
    B -- Yes --> G["Delete local audio file"]
    G --> H["Delete GCS audio blob\n(via API call)"]
    H --> I["Only transcript +\nnotes remain"]

    style G fill:#f96,stroke:#333
    style H fill:#f96,stroke:#333
```

**Storage management thresholds:**

| Threshold     | Remaining Space | Action                                                                                    |
| ------------- | --------------- | ----------------------------------------------------------------------------------------- |
| **Normal**    | > 1 GB          | No action                                                                                 |
| **Warning**   | 500 MB – 1 GB   | Show banner: "Storage running low. Sync recordings to free space."                        |
| **Critical**  | 200 MB – 500 MB | Auto-delete oldest already-uploaded audio chunks. Reduce chunk quality to 64 kbps.        |
| **Emergency** | < 200 MB        | Pause recording. Show blocking dialog: "Not enough storage to continue. Free space now."  |

### 3.6 Sync Engine Architecture

```mermaid
flowchart TD
    subgraph "Sync Engine"
        CE["Connectivity Event<br/>(online detected)"] --> SQ["Process Sync Queue"]
        SQ --> PRI["Priority Sort:<br/>1. Auth tokens<br/>2. Chunk uploads<br/>3. Metadata sync<br/>4. Fetch results"]

        PRI --> UP["Upload Pending Chunks<br/>(parallel, max 3)"]
        PRI --> META["Sync Metadata<br/>(recordings, subjects)"]
        PRI --> FETCH["Fetch Completed<br/>Transcripts & Summaries"]

        UP --> OK{"Upload\nSuccess?"}
        OK -- Yes --> MARK["Mark chunk: uploaded"]
        OK -- No --> RETRY["Exponential Backoff\n(30s → 1m → 2m → 5m)"]
        RETRY --> UP

        META --> CONFLICT{"Conflict?"}
        CONFLICT -- No --> MERGE["Apply server changes"]
        CONFLICT -- Yes --> RESOLVE["Conflict Resolution"]
        RESOLVE --> LWW["Last-Write-Wins\n(by updated_at)"]
    end
```

#### 3.6.1 Sync Queue Data Structure

```dart
class SyncQueueItem {
  final String id;              // UUID
  final SyncOperation operation; // create | update | delete
  final String entityType;       // chunk | recording | subject
  final String entityId;         // UUID of the entity
  final int priority;            // 0 = highest
  final int retryCount;          // max 10
  final DateTime createdAt;
  final DateTime? lastAttemptAt;
  final String? errorMessage;
  final Map<String, dynamic> payload; // serialized data
}
```

#### 3.6.2 Conflict Resolution Strategy

| Scenario                              | Resolution                                                             |
| ------------------------------------- | ---------------------------------------------------------------------- |
| Subject renamed on both sides         | Last-Write-Wins (server `updated_at` vs local `updated_at`)           |
| Recording metadata edited offline     | Last-Write-Wins; user notified if server version was newer             |
| Chunk uploaded but server has no record | Re-upload (idempotent — server checks SHA-256 for dedup)             |
| Transcript edited by user on two devices | Server always wins for AI-generated content; user edits merge via OT |

---

## 4. Backend Architecture

### 4.1 Technology Choices

| Component      | Choice                | Rationale                                                            |
| -------------- | --------------------- | -------------------------------------------------------------------- |
| Framework      | **Fastify 5.x**       | 3-5× faster than Express, built-in JSON schema validation, plugin ecosystem |
| ORM            | **Drizzle ORM**       | Type-safe, lightweight, SQL-first; avoids heavy Prisma bundles       |
| Validation     | **Zod + JSON Schema** | Fastify-native schema validation at the route level                  |
| Auth middleware | **Firebase Admin SDK**| Verify ID tokens, manage custom claims                               |
| File uploads   | **@fastify/multipart**| Streaming multipart handling, no temp files on disk                  |
| Job queue      | **BullMQ 5.x**        | Redis-backed, supports delayed/repeated/priority jobs, battle-tested |
| Logger         | **Pino**              | Fastify's default; structured JSON logging, < 1 μs serialisation    |

### 4.2 Backend Project Structure

```
backend-api/
├── src/
│   ├── index.ts                    # Entry point — start Fastify
│   ├── app.ts                      # Fastify app factory (plugins, routes)
│   ├── config/
│   │   ├── env.ts                  # Environment variable validation (Zod)
│   │   ├── database.ts             # PostgreSQL connection pool
│   │   └── redis.ts                # Redis connection
│   │
│   ├── plugins/
│   │   ├── auth.plugin.ts          # Firebase token verification
│   │   ├── rateLimit.plugin.ts     # @fastify/rate-limit config
│   │   ├── cors.plugin.ts          # CORS configuration
│   │   └── errorHandler.plugin.ts  # Global error handler
│   │
│   ├── modules/
│   │   ├── auth/
│   │   │   ├── auth.routes.ts
│   │   │   ├── auth.controller.ts
│   │   │   ├── auth.service.ts
│   │   │   └── auth.schema.ts      # Zod + JSON schema for request/response
│   │   │
│   │   ├── users/
│   │   │   ├── users.routes.ts
│   │   │   ├── users.controller.ts
│   │   │   ├── users.service.ts
│   │   │   └── users.schema.ts
│   │   │
│   │   ├── subjects/
│   │   │   ├── subjects.routes.ts
│   │   │   ├── subjects.controller.ts
│   │   │   ├── subjects.service.ts
│   │   │   └── subjects.schema.ts
│   │   │
│   │   ├── recordings/
│   │   │   ├── recordings.routes.ts
│   │   │   ├── recordings.controller.ts
│   │   │   ├── recordings.service.ts
│   │   │   └── recordings.schema.ts
│   │   │
│   │   ├── chunks/
│   │   │   ├── chunks.routes.ts
│   │   │   ├── chunks.controller.ts
│   │   │   ├── chunks.service.ts
│   │   │   └── chunks.schema.ts
│   │   │
│   │   ├── transcripts/
│   │   │   ├── transcripts.routes.ts
│   │   │   ├── transcripts.controller.ts
│   │   │   ├── transcripts.service.ts
│   │   │   └── transcripts.schema.ts
│   │   │
│   │   └── summaries/
│   │       ├── summaries.routes.ts
│   │       ├── summaries.controller.ts
│   │       ├── summaries.service.ts
│   │       └── summaries.schema.ts
│   │
│   ├── workers/
│   │   ├── stt.worker.ts           # Speech-to-text processor
│   │   ├── assembly.worker.ts      # Chunk transcripts → full transcript
│   │   ├── ai.worker.ts            # Gemini summary generator
│   │   ├── pdf.worker.ts           # PDF renderer
│   │   └── cleanup.worker.ts       # Audio deletion after transcript confirmation
│   │
│   ├── queues/
│   │   ├── queue.registry.ts       # BullMQ queue definitions
│   │   └── queue.events.ts         # Queue event handlers (completed, failed)
│   │
│   ├── db/
│   │   ├── schema.ts               # Drizzle schema definitions
│   │   ├── migrations/             # SQL migration files
│   │   └── seed.ts                 # Seed data for development
│   │
│   ├── lib/
│   │   ├── gcs.ts                  # Google Cloud Storage client
│   │   ├── stt.ts                  # Google STT + Whisper client wrapper
│   │   ├── gemini.ts               # Gemini API client
│   │   ├── fcm.ts                  # Firebase Cloud Messaging sender
│   │   └── pdf.ts                  # Puppeteer PDF generation
│   │
│   └── shared/
│       ├── types.ts                # Shared TypeScript types
│       ├── errors.ts               # Custom error classes
│       └── utils.ts                # Utility functions
│
├── tests/
├── Dockerfile
├── docker-compose.yml
├── drizzle.config.ts
├── tsconfig.json
├── package.json
└── .env.example
```

### 4.3 RESTful API Endpoint Structure

#### 4.3.1 Auth Endpoints

| Method | Path                     | Description                      | Auth Required |
| ------ | ------------------------ | -------------------------------- | ------------- |
| POST   | `/api/v1/auth/register`  | Create user profile after signup | Yes (Firebase) |
| GET    | `/api/v1/auth/me`        | Get current user profile         | Yes           |
| PATCH  | `/api/v1/auth/me`        | Update profile                   | Yes           |
| DELETE | `/api/v1/auth/me`        | Delete account + all data        | Yes           |

#### 4.3.2 Subjects Endpoints

| Method | Path                            | Description             | Auth |
| ------ | ------------------------------- | ----------------------- | ---- |
| GET    | `/api/v1/subjects`              | List user's subjects    | Yes  |
| POST   | `/api/v1/subjects`              | Create subject          | Yes  |
| GET    | `/api/v1/subjects/:id`          | Get subject detail      | Yes  |
| PATCH  | `/api/v1/subjects/:id`          | Update subject          | Yes  |
| DELETE | `/api/v1/subjects/:id`          | Delete subject          | Yes  |

#### 4.3.3 Recordings Endpoints

| Method | Path                                      | Description                          | Auth |
| ------ | ----------------------------------------- | ------------------------------------ | ---- |
| GET    | `/api/v1/recordings`                      | List recordings (filterable)         | Yes  |
| POST   | `/api/v1/recordings`                      | Create recording metadata            | Yes  |
| GET    | `/api/v1/recordings/:id`                  | Get recording with status            | Yes  |
| PATCH  | `/api/v1/recordings/:id`                  | Update recording metadata            | Yes  |
| DELETE | `/api/v1/recordings/:id`                  | Delete recording + cascade           | Yes  |
| POST   | `/api/v1/recordings/:id/process`          | Trigger processing pipeline          | Yes  |
| GET    | `/api/v1/recordings/:id/status`           | Get processing pipeline status       | Yes  |

#### 4.3.4 Chunks Endpoints

| Method | Path                                          | Description                      | Auth |
| ------ | --------------------------------------------- | -------------------------------- | ---- |
| POST   | `/api/v1/recordings/:recordingId/chunks`      | Upload audio chunk (multipart)   | Yes  |
| GET    | `/api/v1/recordings/:recordingId/chunks`      | List chunks for recording        | Yes  |
| GET    | `/api/v1/chunks/:id`                          | Get chunk detail + transcript    | Yes  |
| DELETE | `/api/v1/chunks/:id`                          | Delete chunk                     | Yes  |
| POST   | `/api/v1/chunks/upload-url`                   | Get signed upload URL (resumable)| Yes  |

#### 4.3.5 Transcripts & Summaries Endpoints

| Method | Path                                        | Description                       | Auth |
| ------ | ------------------------------------------- | --------------------------------- | ---- |
| GET    | `/api/v1/recordings/:id/transcript`         | Get assembled full transcript     | Yes  |
| PATCH  | `/api/v1/recordings/:id/transcript`         | Edit transcript (user corrections)| Yes  |
| GET    | `/api/v1/recordings/:id/summary`            | Get AI-generated summary/notes    | Yes  |
| POST   | `/api/v1/recordings/:id/summary/regenerate` | Re-run AI summary generation      | Yes  |
| GET    | `/api/v1/recordings/:id/pdf`                | Download/stream the PDF           | Yes  |
| POST   | `/api/v1/recordings/:id/pdf/regenerate`     | Re-generate PDF                   | Yes  |

#### 4.3.6 Sync Endpoint

| Method | Path                   | Description                                              | Auth |
| ------ | ---------------------- | -------------------------------------------------------- | ---- |
| POST   | `/api/v1/sync`         | Batch sync — client sends changes, receives server state | Yes  |

### 4.4 Authentication & Authorization Flow

```mermaid
sequenceDiagram
    participant App as Flutter App
    participant FB as Firebase Auth
    participant API as Backend API
    participant PG as PostgreSQL

    App->>FB: signInWithEmail(email, password)
    FB-->>App: Firebase ID Token (JWT)

    App->>API: GET /api/v1/auth/me<br/>Authorization: Bearer <idToken>

    API->>FB: verifyIdToken(idToken)
    FB-->>API: DecodedToken { uid, email, ... }

    API->>PG: SELECT * FROM users WHERE firebase_uid = ?

    alt User exists
        PG-->>API: User record
        API-->>App: 200 { user }
    else First login
        API->>PG: INSERT INTO users (firebase_uid, email, ...)
        PG-->>API: New user record
        API-->>App: 201 { user }
    end
```

**Token lifecycle:**
- Firebase ID tokens expire every **60 minutes**.
- The Flutter app uses `FirebaseAuth.instance.currentUser!.getIdToken()` which auto-refreshes transparently.
- The backend verifies tokens on every request via the auth plugin — no session storage.
- **Offline**: The app caches the last valid user profile in SQLite. All local operations proceed without token verification. Tokens are refreshed when the device goes online before any API calls.

### 4.5 Rate Limiting

| Scope          | Limit                    | Window   | Response             |
| -------------- | ------------------------ | -------- | -------------------- |
| Global (IP)    | 100 requests             | 1 minute | `429 Too Many Requests` |
| Auth endpoints | 10 requests              | 1 minute | `429`                |
| Chunk upload   | 30 uploads               | 1 hour   | `429`                |
| AI regenerate  | 5 requests               | 1 hour   | `429`                |
| PDF regenerate | 10 requests              | 1 hour   | `429`                |

Implementation: `@fastify/rate-limit` with Redis store for distributed rate limiting across Cloud Run instances.

### 4.6 Request / Response Patterns

#### Standard Success Response

```json
{
  "success": true,
  "data": { ... },
  "meta": {
    "requestId": "req_abc123",
    "timestamp": "2026-07-07T01:00:00.000Z"
  }
}
```

#### Paginated List Response

```json
{
  "success": true,
  "data": [ ... ],
  "pagination": {
    "page": 1,
    "pageSize": 20,
    "totalItems": 142,
    "totalPages": 8
  },
  "meta": {
    "requestId": "req_abc123",
    "timestamp": "2026-07-07T01:00:00.000Z"
  }
}
```

#### Error Response

```json
{
  "success": false,
  "error": {
    "code": "CHUNK_UPLOAD_FAILED",
    "message": "The audio chunk could not be stored. Please retry.",
    "details": {
      "chunkIndex": 3,
      "reason": "GCS_WRITE_ERROR"
    }
  },
  "meta": {
    "requestId": "req_abc123",
    "timestamp": "2026-07-07T01:00:00.000Z"
  }
}
```

### 4.7 Error Handling Standards

```mermaid
flowchart TD
    REQ["Incoming Request"] --> VAL{"Schema\nValid?"}
    VAL -- No --> R400["400 Bad Request<br/>+ validation errors"]
    VAL -- Yes --> AUTH{"Auth\nValid?"}
    AUTH -- No --> R401["401 Unauthorized"]
    AUTH -- Yes --> AUTHZ{"Has\nPermission?"}
    AUTHZ -- No --> R403["403 Forbidden"]
    AUTHZ -- Yes --> HANDLER["Route Handler"]
    HANDLER --> BL{"Business Logic\nError?"}
    BL -- Yes --> R4XX["4xx with error code"]
    BL -- No --> EXT{"External Service\nFailure?"}
    EXT -- Yes --> R502["502 Bad Gateway<br/>or 503 Service Unavailable"]
    EXT -- No --> R200["200 OK / 201 Created"]

    HANDLER -- "Uncaught Exception" --> R500["500 Internal Server Error<br/>(generic message, details logged)"]
```

**Error code taxonomy:**

| HTTP Status | Error Code Prefix | Example                        |
| ----------- | ----------------- | ------------------------------ |
| 400         | `VALIDATION_*`    | `VALIDATION_MISSING_FIELD`     |
| 401         | `AUTH_*`          | `AUTH_TOKEN_EXPIRED`           |
| 403         | `FORBIDDEN_*`     | `FORBIDDEN_NOT_OWNER`          |
| 404         | `NOT_FOUND_*`     | `NOT_FOUND_RECORDING`          |
| 409         | `CONFLICT_*`      | `CONFLICT_DUPLICATE_CHUNK`     |
| 413         | `PAYLOAD_*`       | `PAYLOAD_TOO_LARGE`            |
| 429         | `RATE_LIMIT_*`    | `RATE_LIMIT_EXCEEDED`          |
| 500         | `INTERNAL_*`      | `INTERNAL_SERVER_ERROR`        |
| 502         | `UPSTREAM_*`      | `UPSTREAM_STT_FAILURE`         |
| 503         | `SERVICE_*`       | `SERVICE_UNAVAILABLE`          |

### 4.8 Background Job Processing

```mermaid
flowchart LR
    subgraph "BullMQ Queues (Redis-backed)"
        Q1["stt-queue<br/>(priority: high)"]
        Q2["assembly-queue<br/>(priority: medium)"]
        Q3["ai-queue<br/>(priority: medium)"]
        Q4["pdf-queue<br/>(priority: low)"]
        Q5["cleanup-queue<br/>(priority: low)"]
    end

    subgraph "Workers (Cloud Run Jobs)"
        W1["STT Worker<br/>(concurrency: 10)"]
        W2["Assembly Worker<br/>(concurrency: 5)"]
        W3["AI Worker<br/>(concurrency: 5)"]
        W4["PDF Worker<br/>(concurrency: 3)"]
        W5["Cleanup Worker<br/>(concurrency: 5)"]
    end

    Q1 --> W1
    Q2 --> W2
    Q3 --> W3
    Q4 --> W4
    Q5 --> W5
```

**Job lifecycle:**

```mermaid
stateDiagram-v2
    [*] --> Waiting
    Waiting --> Active: Worker picks up
    Active --> Completed: Success
    Active --> Failed: Error thrown
    Failed --> Waiting: Auto-retry (backoff)
    Failed --> Dead: Max retries exceeded
    Dead --> [*]: Alert fired
    Completed --> [*]

    note right of Failed
        Retry policy:
        - Max attempts: 5
        - Backoff: exponential
        - Delays: 10s, 30s, 90s, 270s, 810s
    end note
```

**Job payloads:**

| Queue       | Payload                                                                                  |
| ----------- | ---------------------------------------------------------------------------------------- |
| `stt`       | `{ chunkId, recordingId, gcsUri, codec, sampleRate, languageCode }`                      |
| `assembly`  | `{ recordingId, chunkIds[] }`                                                            |
| `ai`        | `{ recordingId, transcriptText, promptTemplate, outputFormat }`                          |
| `pdf`       | `{ recordingId, summaryMarkdown, templateId, userId }`                                   |
| `cleanup`   | `{ chunkId, gcsUri }`                                                                    |

---

## 5. Data Architecture

### 5.1 PostgreSQL Schema Design

```mermaid
erDiagram
    users ||--o{ subjects : "has many"
    users ||--o{ recordings : "owns"
    subjects ||--o{ recordings : "categorizes"
    recordings ||--o{ chunks : "split into"
    recordings ||--|| transcripts : "has one"
    recordings ||--|| summaries : "has one"
    recordings ||--o{ pdfs : "exports to"
    chunks ||--o| chunk_transcripts : "transcribed to"

    users {
        uuid id PK
        varchar firebase_uid UK
        varchar email UK
        varchar display_name
        varchar avatar_url
        jsonb preferences
        timestamp created_at
        timestamp updated_at
    }

    subjects {
        uuid id PK
        uuid user_id FK
        varchar name
        varchar color_hex
        varchar icon
        text description
        timestamp created_at
        timestamp updated_at
    }

    recordings {
        uuid id PK
        uuid user_id FK
        uuid subject_id FK
        varchar title
        text description
        varchar status
        integer total_chunks
        integer processed_chunks
        bigint total_duration_ms
        varchar language_code
        timestamp recorded_at
        timestamp created_at
        timestamp updated_at
    }

    chunks {
        uuid id PK
        uuid recording_id FK
        integer chunk_index
        varchar status
        varchar gcs_uri
        varchar file_checksum_sha256
        bigint file_size_bytes
        bigint duration_ms
        bigint start_offset_ms
        integer retry_count
        text error_message
        timestamp created_at
        timestamp updated_at
    }

    chunk_transcripts {
        uuid id PK
        uuid chunk_id FK
        text transcript_text
        jsonb word_timestamps
        real confidence_score
        varchar stt_provider
        timestamp created_at
    }

    transcripts {
        uuid id PK
        uuid recording_id FK
        text full_text
        jsonb sections
        varchar status
        bigint word_count
        timestamp created_at
        timestamp updated_at
    }

    summaries {
        uuid id PK
        uuid recording_id FK
        text summary_markdown
        jsonb key_topics
        jsonb flashcards
        varchar status
        varchar ai_model_version
        integer token_count
        timestamp created_at
        timestamp updated_at
    }

    pdfs {
        uuid id PK
        uuid recording_id FK
        varchar gcs_uri
        bigint file_size_bytes
        varchar template_id
        varchar status
        timestamp created_at
    }
```

### 5.2 PostgreSQL DDL (Core Tables)

```sql
-- Enable UUID generation
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ============================================================
-- USERS
-- ============================================================
CREATE TABLE users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    firebase_uid    VARCHAR(128) NOT NULL UNIQUE,
    email           VARCHAR(320) NOT NULL UNIQUE,
    display_name    VARCHAR(100),
    avatar_url      TEXT,
    preferences     JSONB NOT NULL DEFAULT '{}',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_users_firebase_uid ON users (firebase_uid);

-- ============================================================
-- SUBJECTS
-- ============================================================
CREATE TABLE subjects (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id         UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    name            VARCHAR(200) NOT NULL,
    color_hex       VARCHAR(7) NOT NULL DEFAULT '#4A90D9',
    icon            VARCHAR(50) DEFAULT 'book',
    description     TEXT,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_subjects_user_id ON subjects (user_id);

-- ============================================================
-- RECORDINGS
-- ============================================================
CREATE TYPE recording_status AS ENUM (
    'recording',          -- currently being recorded
    'pending_upload',     -- recorded, chunks not yet all uploaded
    'uploading',          -- chunks currently uploading
    'pending_processing', -- all chunks uploaded, awaiting STT
    'processing_stt',     -- STT in progress
    'processing_assembly',-- assembling chunk transcripts
    'processing_ai',      -- AI summary generation in progress
    'processing_pdf',     -- PDF rendering in progress
    'completed',          -- full pipeline done
    'partial_failure',    -- some chunks failed, partial transcript available
    'failed'              -- complete pipeline failure
);

CREATE TABLE recordings (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id             UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    subject_id          UUID REFERENCES subjects(id) ON DELETE SET NULL,
    title               VARCHAR(500) NOT NULL,
    description         TEXT,
    status              recording_status NOT NULL DEFAULT 'recording',
    total_chunks        INTEGER NOT NULL DEFAULT 0,
    processed_chunks    INTEGER NOT NULL DEFAULT 0,
    total_duration_ms   BIGINT NOT NULL DEFAULT 0,
    language_code       VARCHAR(10) NOT NULL DEFAULT 'en-US',
    recorded_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_recordings_user_id ON recordings (user_id);
CREATE INDEX idx_recordings_subject_id ON recordings (subject_id);
CREATE INDEX idx_recordings_status ON recordings (status);
CREATE INDEX idx_recordings_recorded_at ON recordings (user_id, recorded_at DESC);

-- ============================================================
-- CHUNKS
-- ============================================================
CREATE TYPE chunk_status AS ENUM (
    'pending_upload',     -- exists locally, not yet uploaded
    'uploading',          -- upload in progress
    'uploaded',           -- in GCS, awaiting STT
    'processing',         -- STT running
    'transcribed',        -- STT completed
    'failed',             -- STT failed after all retries
    'audio_deleted'       -- audio removed after transcript confirmed
);

CREATE TABLE chunks (
    id                      UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recording_id            UUID NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
    chunk_index             INTEGER NOT NULL,
    status                  chunk_status NOT NULL DEFAULT 'pending_upload',
    gcs_uri                 TEXT,
    file_checksum_sha256    VARCHAR(64),
    file_size_bytes         BIGINT,
    duration_ms             BIGINT,
    start_offset_ms         BIGINT NOT NULL DEFAULT 0,
    retry_count             INTEGER NOT NULL DEFAULT 0,
    error_message           TEXT,
    created_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at              TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    UNIQUE (recording_id, chunk_index)
);

CREATE INDEX idx_chunks_recording_id ON chunks (recording_id);
CREATE INDEX idx_chunks_status ON chunks (status);

-- ============================================================
-- CHUNK TRANSCRIPTS
-- ============================================================
CREATE TABLE chunk_transcripts (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    chunk_id            UUID NOT NULL UNIQUE REFERENCES chunks(id) ON DELETE CASCADE,
    transcript_text     TEXT NOT NULL,
    word_timestamps     JSONB,   -- [{word, startMs, endMs, confidence}, ...]
    confidence_score    REAL,    -- average confidence 0.0–1.0
    stt_provider        VARCHAR(20) NOT NULL DEFAULT 'google',  -- 'google' | 'whisper'
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_chunk_transcripts_chunk_id ON chunk_transcripts (chunk_id);

-- ============================================================
-- TRANSCRIPTS (assembled full transcript per recording)
-- ============================================================
CREATE TYPE transcript_status AS ENUM (
    'pending', 'assembling', 'completed', 'failed'
);

CREATE TABLE transcripts (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recording_id    UUID NOT NULL UNIQUE REFERENCES recordings(id) ON DELETE CASCADE,
    full_text       TEXT,
    sections        JSONB,          -- [{title, startMs, endMs, text}, ...]
    status          transcript_status NOT NULL DEFAULT 'pending',
    word_count      BIGINT DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- SUMMARIES (AI-generated study notes)
-- ============================================================
CREATE TYPE summary_status AS ENUM (
    'pending', 'generating', 'completed', 'failed'
);

CREATE TABLE summaries (
    id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recording_id        UUID NOT NULL UNIQUE REFERENCES recordings(id) ON DELETE CASCADE,
    summary_markdown    TEXT,
    key_topics          JSONB,      -- ["Topic A", "Topic B", ...]
    flashcards          JSONB,      -- [{question, answer}, ...]
    status              summary_status NOT NULL DEFAULT 'pending',
    ai_model_version    VARCHAR(50),
    token_count         INTEGER DEFAULT 0,
    created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- PDFs
-- ============================================================
CREATE TYPE pdf_status AS ENUM (
    'pending', 'generating', 'completed', 'failed'
);

CREATE TABLE pdfs (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    recording_id    UUID NOT NULL REFERENCES recordings(id) ON DELETE CASCADE,
    gcs_uri         TEXT,
    file_size_bytes BIGINT,
    template_id     VARCHAR(50) NOT NULL DEFAULT 'default',
    status          pdf_status NOT NULL DEFAULT 'pending',
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_pdfs_recording_id ON pdfs (recording_id);
```

### 5.3 Key Indexes & Query Optimisation

| Query Pattern                                  | Index                                                      |
| ---------------------------------------------- | ---------------------------------------------------------- |
| Dashboard: user's recent recordings            | `idx_recordings_recorded_at (user_id, recorded_at DESC)`   |
| Filter recordings by subject                   | `idx_recordings_subject_id (subject_id)`                   |
| Pipeline: find chunks pending processing       | `idx_chunks_status (status)`                               |
| Lookup user by Firebase UID on every request   | `idx_users_firebase_uid (firebase_uid)` — UNIQUE           |
| Assemble transcript: fetch chunks in order     | `UNIQUE (recording_id, chunk_index)` — used as sort        |

### 5.4 SQLite Local Schema

The local SQLite database mirrors the cloud schema **exactly** (same table names, same columns) with the following additions to every table:

```sql
-- Added to EVERY local table:
sync_status      TEXT NOT NULL DEFAULT 'synced',
    -- Values: 'synced' | 'pending_create' | 'pending_update' | 'pending_delete' | 'conflict'
local_updated_at TEXT NOT NULL DEFAULT (datetime('now')),
server_updated_at TEXT,

-- Chunk-specific local columns:
local_file_path  TEXT,           -- e.g., /data/user/0/com.lecto.app/files/chunks/abc123.m4a
upload_progress  REAL DEFAULT 0  -- 0.0 to 1.0
```

**Implementation**: The Drift package (Dart) generates type-safe DAOs from Dart table definitions. Migrations are versioned and run on app startup.

### 5.5 Data Sync Strategy

```mermaid
sequenceDiagram
    participant App as Flutter App
    participant Local as SQLite
    participant API as Backend API
    participant PG as PostgreSQL

    Note over App: App comes online or periodic sync
    App->>Local: SELECT * WHERE sync_status != 'synced'
    Local-->>App: Pending changes (creates, updates, deletes)

    App->>API: POST /api/v1/sync<br/>{<br/>  creates: [...],<br/>  updates: [...],<br/>  deletes: [...],<br/>  lastSyncTimestamp: "2026-07-06T..."<br/>}

    API->>PG: Apply creates/updates/deletes
    API->>PG: SELECT * WHERE updated_at > lastSyncTimestamp<br/>AND user_id = ?
    PG-->>API: Server-side changes since last sync

    API-->>App: {<br/>  applied: { creates: 3, updates: 1, deletes: 0 },<br/>  serverChanges: [...],<br/>  conflicts: [...],<br/>  newSyncTimestamp: "2026-07-07T..."<br/>}

    App->>Local: Apply server changes
    App->>Local: Mark all synced items as 'synced'
    App->>Local: Store newSyncTimestamp

    alt Conflicts detected
        App->>App: Apply conflict resolution (LWW)
        App->>Local: Resolve conflict records
    end
```

### 5.6 Data Lifecycle

```mermaid
flowchart LR
    A["🎙️ Audio Recording<br/>(on device)"] -->|"Chunk & Upload"| B["☁️ Audio in GCS<br/>(temporary)"]
    B -->|"STT Processing"| C["📝 Chunk Transcript<br/>(in PostgreSQL)"]
    C -->|"Assembly"| D["📄 Full Transcript<br/>(main.md in PG)"]
    D -->|"Gemini AI"| E["📋 Study Notes<br/>(markdown in PG)"]
    E -->|"Puppeteer"| F["📕 PDF File<br/>(in GCS, permanent)"]

    B -.->|"DELETE after<br/>transcript confirmed"| X1["🗑️"]
    A -.->|"DELETE after<br/>upload confirmed"| X2["🗑️"]

    style X1 fill:#ff6b6b,stroke:#333
    style X2 fill:#ff6b6b,stroke:#333
    style F fill:#51cf66,stroke:#333
```

**Retention policy:**

| Data Type            | Location    | Retention                                    |
| -------------------- | ----------- | -------------------------------------------- |
| Audio chunks (local) | Device      | Deleted after upload confirmed by server     |
| Audio chunks (cloud) | GCS         | Deleted 24h after transcript confirmed       |
| Chunk transcripts    | PostgreSQL  | Permanent (until recording deleted)          |
| Full transcript      | PostgreSQL  | Permanent                                    |
| AI summary           | PostgreSQL  | Permanent                                    |
| PDF files            | GCS         | Permanent (until recording deleted)          |
| User account data    | PostgreSQL  | Deleted 30 days after account deletion request |

---

## 6. Processing Pipeline

### 6.1 Complete Pipeline Overview

```mermaid
flowchart TD
    START["Recording Completed<br/>All chunks uploaded"] --> DISPATCH["Pipeline Dispatcher"]

    DISPATCH --> STT_JOBS["Enqueue N STT Jobs<br/>(one per chunk, parallel)"]

    STT_JOBS --> STT1["STT Chunk 1"]
    STT_JOBS --> STT2["STT Chunk 2"]
    STT_JOBS --> STTN["STT Chunk N"]

    STT1 --> CHECK{"All chunks<br/>transcribed?"}
    STT2 --> CHECK
    STTN --> CHECK

    CHECK -- "Yes" --> ASSEMBLE["Assembly Job<br/>Merge chunks → full transcript"]
    CHECK -- "No (some failed)" --> PARTIAL["Partial Assembly<br/>(skip failed chunks,<br/>mark gaps)"]

    ASSEMBLE --> AI_JOB["AI Summary Job<br/>(Gemini API)"]
    PARTIAL --> AI_JOB

    AI_JOB --> PDF_JOB["PDF Generation Job<br/>(Puppeteer)"]

    PDF_JOB --> CLEANUP["Cleanup Job<br/>(Delete audio from GCS)"]

    CLEANUP --> NOTIFY["Send Push Notification<br/>'Your notes are ready!'"]

    NOTIFY --> DONE["✅ Pipeline Complete"]

    STT1 -. "failure after retries" .-> FALLBACK1["Whisper Fallback"]
    FALLBACK1 --> CHECK
```

### 6.2 Audio Chunk Upload Flow

```mermaid
sequenceDiagram
    participant App as Flutter App
    participant API as Backend API
    participant GCS as Cloud Storage

    App->>API: POST /chunks/upload-url<br/>{ recordingId, chunkIndex, fileSize, checksum }
    API->>GCS: Generate signed resumable upload URL (1h expiry)
    GCS-->>API: Signed URL
    API-->>App: { uploadUrl, chunkId }

    App->>GCS: PUT (resumable upload, chunked)<br/>Content-Type: audio/mp4
    Note over App,GCS: Resumable upload supports<br/>network interruptions

    alt Upload succeeds
        GCS-->>App: 200 OK
        App->>API: PATCH /chunks/:chunkId<br/>{ status: 'uploaded', gcsUri }
        API-->>App: 200 OK
    else Upload interrupted
        Note over App: App stores resumable upload URI
        App->>GCS: PUT (resume from last byte)
        GCS-->>App: 200 OK
    end
```

**Design decisions:**
- **Signed URLs**: The app uploads directly to GCS via signed URLs, bypassing the API server for large file transfers. This prevents API server memory pressure and enables resumable uploads.
- **Resumable uploads**: GCS resumable uploads allow the app to resume interrupted transfers from the last successfully written byte — critical for poor connectivity.
- **Checksum verification**: The server compares the client-provided SHA-256 with the GCS object's hash after upload to detect corruption.

### 6.3 Speech-to-Text Processing Pipeline

```mermaid
flowchart TD
    JOB["STT Job Received<br/>{ chunkId, gcsUri }"] --> FETCH["Read audio from GCS"]
    FETCH --> DETECT["Detect audio properties<br/>(sample rate, codec, channels)"]
    DETECT --> PRIMARY["Google Cloud STT<br/>RecognizeRequest"]

    PRIMARY --> RESULT{"STT\nSuccess?"}

    RESULT -- "Yes" --> SAVE["Save to chunk_transcripts<br/>(text, word_timestamps,<br/>confidence, provider='google')"]

    RESULT -- "No (error)" --> RETRY{"Retries\n< 3?"}
    RETRY -- "Yes" --> PRIMARY

    RETRY -- "No" --> FALLBACK["OpenAI Whisper API<br/>(fallback)"]
    FALLBACK --> RESULT2{"Whisper\nSuccess?"}
    RESULT2 -- "Yes" --> SAVE2["Save to chunk_transcripts<br/>(provider='whisper')"]
    RESULT2 -- "No" --> FAIL["Mark chunk: failed<br/>Log error, alert"]

    SAVE --> UPDATE["Update chunk status: transcribed"]
    SAVE2 --> UPDATE
    UPDATE --> PIPELINE["Check: all chunks done?<br/>If yes → enqueue assembly"]
```

**Google Cloud STT configuration:**

```typescript
const sttConfig = {
  encoding: 'MP4',                     // matches AAC in .m4a
  sampleRateHertz: 44100,
  languageCode: 'en-US',               // user-configurable
  model: 'latest_long',                // optimized for long-form audio
  enableAutomaticPunctuation: true,
  enableWordTimeOffsets: true,          // for word-level timestamps
  enableWordConfidence: true,
  useEnhanced: true,                   // enhanced model for better accuracy
  alternativeLanguageCodes: ['en-GB'], // support common variants
  maxAlternatives: 1,
};
```

### 6.4 Transcript Assembly

```mermaid
flowchart TD
    TRIGGER["Assembly Job<br/>{ recordingId }"] --> FETCH["Fetch all chunk_transcripts<br/>ORDER BY chunk_index ASC"]
    FETCH --> GAPS{"Any chunks<br/>failed?"}

    GAPS -- "No" --> CONCAT["Concatenate transcript texts<br/>with paragraph breaks"]
    GAPS -- "Yes" --> INSERT_GAP["Insert gap markers:<br/>'[~2 min gap — audio<br/>could not be transcribed]'"]
    INSERT_GAP --> CONCAT

    CONCAT --> FORMAT["Apply formatting:<br/>- Smart paragraph breaks<br/>- Speaker diarization hints<br/>- Timestamp markers every 5 min"]

    FORMAT --> SECTION["Auto-detect sections<br/>(topic shifts via keyword analysis)"]

    SECTION --> SAVE["Save to transcripts table<br/>{full_text, sections[], word_count}"]
    SAVE --> STATUS["Update recording status:<br/>'processing_ai'"]
    STATUS --> ENQUEUE["Enqueue AI Summary job"]
```

### 6.5 AI Summary Generation Pipeline

```mermaid
flowchart TD
    JOB["AI Job Received<br/>{ recordingId, transcriptText }"] --> PREP["Prepare prompt"]

    PREP --> SIZE{"Transcript<br/>> 100K tokens?"}
    SIZE -- "Yes" --> SPLIT["Split into overlapping<br/>sections (90K + 10K overlap)"]
    SPLIT --> MULTI["Process each section<br/>separately, then merge"]
    SIZE -- "No" --> SINGLE["Process in single call"]

    SINGLE --> CALL["Gemini API Call<br/>model: gemini-2.0-pro"]
    MULTI --> CALL

    CALL --> PARSE["Parse structured response:<br/>- Summary markdown<br/>- Key topics array<br/>- Flashcards array"]

    PARSE --> VALIDATE{"Response\nvalid?"}
    VALIDATE -- "Yes" --> SAVE["Save to summaries table"]
    VALIDATE -- "No" --> RETRY{"Retries\n< 3?"}
    RETRY -- "Yes" --> CALL
    RETRY -- "No" --> FAIL["Mark summary: failed<br/>Transcript still available"]

    SAVE --> ENQUEUE["Enqueue PDF generation"]
```

**Gemini prompt template:**

```
You are an expert academic note-taking assistant. Given the following lecture transcript, 
produce structured study notes in Markdown format.

## Requirements:
1. **Summary** (2-3 paragraphs): High-level overview of the lecture content
2. **Key Topics**: Bulleted list of main topics covered
3. **Detailed Notes**: Organized by topic with:
   - Clear headings and subheadings
   - Key definitions highlighted in **bold**
   - Important formulas or concepts in `code blocks`
   - Examples from the lecture
4. **Flashcards**: Generate 10-20 Q&A flashcards from the content
   Format: [{"question": "...", "answer": "..."}]
5. **Action Items**: Any assignments, readings, or tasks mentioned

## Transcript:
{transcript_text}

## Output Format:
Return ONLY valid JSON with keys: summary, keyTopics, detailedNotes, flashcards, actionItems
```

### 6.6 PDF Generation Pipeline

```mermaid
flowchart TD
    JOB["PDF Job<br/>{ recordingId, summaryMarkdown }"] --> TEMPLATE["Load HTML template<br/>(branded, styled)"]
    TEMPLATE --> RENDER["Render markdown → HTML<br/>(marked.js)"]
    RENDER --> INJECT["Inject into template:<br/>- Header (title, subject, date)<br/>- Summary notes<br/>- Flashcards section<br/>- Footer (page numbers)"]
    INJECT --> PUPPETEER["Puppeteer.launch()<br/>page.setContent(html)<br/>page.pdf(options)"]
    PUPPETEER --> UPLOAD["Upload PDF to GCS<br/>Bucket: lecto-pdfs/"]
    UPLOAD --> SAVE["Save PDF record<br/>(gcsUri, fileSize)"]
    SAVE --> STATUS["Update recording status:<br/>'completed'"]
    STATUS --> NOTIFY["Enqueue push notification"]
```

**Puppeteer PDF options:**

```typescript
const pdfOptions = {
  format: 'A4',
  printBackground: true,
  margin: { top: '20mm', right: '15mm', bottom: '20mm', left: '15mm' },
  displayHeaderFooter: true,
  headerTemplate: '<div style="font-size:9px;text-align:center;width:100%;">Lecto Study Notes</div>',
  footerTemplate: '<div style="font-size:9px;text-align:center;width:100%;"><span class="pageNumber"></span> / <span class="totalPages"></span></div>',
};
```

### 6.7 Retry & Error Handling per Pipeline Stage

| Stage            | Max Retries | Backoff            | Fallback                                                    | On Final Failure                                         |
| ---------------- | ----------- | ------------------ | ----------------------------------------------------------- | -------------------------------------------------------- |
| Chunk Upload     | ∞ (resumable)| Client-side exponential | Resumable upload from last byte                          | Stays in queue until manual cancel                       |
| STT (Google)     | 3           | 10s, 30s, 90s      | Switch to Whisper API                                       | Mark chunk as `failed`, continue pipeline without it     |
| STT (Whisper)    | 2           | 15s, 60s           | None                                                        | Mark chunk as `failed`, insert gap marker in transcript  |
| Assembly         | 2           | 5s, 15s            | None                                                        | Mark transcript as `failed`, notify user                 |
| AI Summary       | 3           | 30s, 90s, 300s     | Simpler prompt with smaller model                           | Mark summary as `failed`, transcript still viewable      |
| PDF Generation   | 3           | 10s, 30s, 90s      | Plain-text PDF (no styled template)                         | Mark PDF as `failed`, notes still readable in-app        |
| Audio Cleanup    | 5           | 1m, 5m, 15m, 1h, 6h | Cron job sweeps for undeleted blobs older than 7 days     | Alert ops team                                           |

---

## 7. Offline-First Architecture

### 7.1 Design Philosophy

> **The app must function perfectly with zero connectivity.** Students are frequently in lecture halls, basements, or rural areas with no internet. The app records, stores, and queues everything locally. Network is treated as an **optimisation** for processing, not a requirement for recording.

### 7.2 Offline Recording Flow

```mermaid
flowchart TD
    START["Student taps Record"] --> CHECK_STORAGE{"Sufficient<br/>local storage?"}
    CHECK_STORAGE -- "Yes" --> RECORD["Begin recording<br/>(local audio file)"]
    CHECK_STORAGE -- "No" --> WARN["Show storage warning<br/>Offer to free space"]

    RECORD --> CHUNK["Auto-chunk every 15 min"]
    CHUNK --> SAVE["Save chunk to local FS<br/>+ SQLite record<br/>(sync_status: pending_create)"]

    SAVE --> ONLINE{"Device<br/>online?"}
    ONLINE -- "Yes" --> UPLOAD["Start background upload<br/>(non-blocking)"]
    ONLINE -- "No" --> QUEUE["Add to sync queue<br/>(will process later)"]

    UPLOAD --> CONTINUE["Continue recording"]
    QUEUE --> CONTINUE
    CONTINUE --> CHUNK
```

### 7.3 Local Processing Queue

```mermaid
flowchart TD
    subgraph "Sync Queue (SQLite Table)"
        SQ["sync_queue table<br/>id, entity_type, entity_id,<br/>operation, priority, payload,<br/>retry_count, next_attempt_at"]
    end

    subgraph "Queue Processor"
        CP["ConnectivityService<br/>(listens for network changes)"]
        CP -->|"Online detected"| PROC["SyncQueueProcessor"]
        PROC --> SORT["Sort by priority:<br/>1. Metadata (recordings, subjects)<br/>2. Chunk uploads<br/>3. Fetch results"]
        SORT --> EXEC["Execute operations<br/>(with concurrency limit = 3)"]
        EXEC --> SUCCESS{"Success?"}
        SUCCESS -- "Yes" --> REMOVE["Remove from queue"]
        SUCCESS -- "No" --> BACKOFF["Increment retry_count<br/>Set next_attempt_at<br/>(exponential backoff)"]
    end

    subgraph "Background Tasks"
        BG1["WorkManager (Android)<br/>Periodic sync every 15 min"]
        BG2["BGTaskScheduler (iOS)<br/>Background fetch"]
    end

    BG1 --> PROC
    BG2 --> PROC
```

### 7.4 Connectivity Detection & State Machine

```mermaid
stateDiagram-v2
    [*] --> Unknown
    Unknown --> Online: Network check succeeds
    Unknown --> Offline: Network check fails

    Online --> Offline: Connectivity lost
    Offline --> Online: Connectivity restored

    Online --> Degraded: High latency / packet loss
    Degraded --> Online: Connection stabilises
    Degraded --> Offline: Connection drops

    state Online {
        [*] --> Idle
        Idle --> Syncing: Pending items in queue
        Syncing --> Idle: Queue empty
        Syncing --> Uploading: Chunk uploads in progress
        Uploading --> Syncing: Upload batch complete
    }
```

**Detection method**: The app pings `https://api.lecto.app/health` every 30 seconds when in the foreground. Additionally, it listens to the platform connectivity stream (`connectivity_plus` package) for immediate network change events. A connection is considered "degraded" if ping latency exceeds 5 seconds or 3 consecutive pings fail.

### 7.5 Conflict Resolution — Detailed

| Scenario                                        | Detection                                               | Resolution                                                                              |
| ----------------------------------------------- | ------------------------------------------------------- | --------------------------------------------------------------------------------------- |
| Recording title edited offline on device A; also edited on device B while online | `server_updated_at > local_server_updated_at` | **Last-Write-Wins**: Server version takes precedence. Local change stored in `conflicts` table for user review. |
| Subject deleted on server while device was offline, device made new recording under that subject | Sync response: `subject_id` returns 404 | Orphan recording: set `subject_id = NULL`, notify user to reassign. |
| Same chunk uploaded from two devices (e.g., user reinstalled app) | Server checks `(recording_id, chunk_index)` unique constraint + SHA-256 match | If checksum matches: idempotent, return existing chunk ID. If different: reject with `409 CONFLICT`. |
| Transcript manually edited offline; AI regeneration happened on server | `transcripts.updated_at` mismatch | **User-edits always preserved**: User-edited transcript stored in `user_edited_text` column; AI version in `full_text`. User can toggle between versions. |

### 7.6 Storage Management

```mermaid
flowchart TD
    MONITOR["StorageMonitorService<br/>(checks every 60 seconds)"] --> CALC["Calculate:<br/>- Total device storage<br/>- Available storage<br/>- Lecto app usage<br/>- Pending upload size"]

    CALC --> NORMAL{"Available<br/>> 1 GB?"}
    NORMAL -- "Yes" --> OK["✅ Normal operation"]
    NORMAL -- "No" --> WARN{"Available<br/>> 500 MB?"}

    WARN -- "Yes" --> BANNER["⚠️ Show warning banner<br/>'Sync recordings to<br/>free up space'"]
    WARN -- "No" --> CRIT{"Available<br/>> 200 MB?"}

    CRIT -- "Yes" --> AUTO_CLEAN["🧹 Auto-delete:<br/>- Uploaded chunks<br/>- Reduce bitrate to 64kbps<br/>- Show persistent warning"]
    CRIT -- "No" --> EMERGENCY["🛑 Emergency:<br/>- Pause active recording<br/>- Block new recordings<br/>- Force sync dialog"]
```

---

## 8. Exception Handling Matrix

> [!IMPORTANT]
> This matrix documents **every anticipated failure scenario** in the system, along with its detection, impact, recovery, and user communication strategy.

### 8.1 Recording Phase Exceptions

| # | Scenario | Detection Method | User Impact | Recovery Strategy | User Communication |
|---|----------|-----------------|-------------|-------------------|-------------------|
| 1 | **No internet during recording** | `ConnectivityService` detects offline state | **None** — recording continues normally | Chunks queued locally; uploaded when online | Subtle offline indicator icon; no interruption |
| 2 | **App killed mid-recording (user swipe or OS)** | On next launch, `RecoveryService` reads `recording_state.json` marker file | Potential loss of last 30s of audio (since last file flush) | Salvage partial chunk: verify file integrity → if valid header + > 10s audio → mark as valid chunk; update recording metadata | Toast: "Your previous recording was recovered. Last few seconds may be missing." |
| 3 | **Phone runs out of storage** | `StorageMonitorService` polling + platform `NSFileManager`/`StatFs` | Recording stops; data loss of current buffer (~1-5s) | Emergency: finalize current chunk, save what's written, stop recording gracefully | Alert dialog: "Storage full. Recording saved up to this point. Please free space." |
| 4 | **Battery dies during recording** | Not detectable in real-time | Loss of current audio buffer (last ~5s). SQLite WAL file may not be flushed. | Same as #2: `RecoveryService` on next launch. SQLite WAL recovery is automatic. Chunk file integrity check. | Same as #2 |
| 5 | **Microphone permission revoked mid-recording** | Platform error callback on audio stream | Recording stops immediately | Finalize current chunk, save state | Alert: "Microphone access was revoked. Recording saved. Please re-enable in Settings." |
| 6 | **Another app takes audio focus (phone call)** | Audio session interruption callback (`AVAudioSession` / `AudioManager`) | Recording pauses | Auto-pause recording; auto-resume when focus returns; insert timestamp marker | Toast: "Recording paused due to phone call. Resumed automatically." |
| 7 | **Corrupt audio chunk (encoding failure)** | Post-write integrity check: file size > 0, valid container header, duration > 0 | One chunk's audio lost | Mark chunk as `corrupt`, skip in pipeline, insert gap marker in transcript | Silent — user sees gap marker in transcript with note: "Audio segment could not be processed" |

### 8.2 Upload Phase Exceptions

| # | Scenario | Detection Method | User Impact | Recovery Strategy | User Communication |
|---|----------|-----------------|-------------|-------------------|-------------------|
| 8 | **Internet drops during upload** | HTTP timeout / connection reset exception | Upload paused; chunk not yet on server | GCS resumable upload: resume from last byte on reconnect. Exponential backoff: 30s → 1m → 5m. | Progress bar shows "Paused — waiting for connection" |
| 9 | **Upload succeeds but server doesn't acknowledge** | API returns non-200 or request times out after GCS upload completes | Chunk in GCS but not tracked in DB | Client retries the `PATCH /chunks/:id` status update. Server checks GCS for blob existence. Idempotent. | Upload shows as "Verifying…" then completes |
| 10 | **Checksum mismatch after upload** | Server compares client SHA-256 with GCS object hash | Corrupted upload | Delete GCS blob, re-upload from local file | "Upload verification failed. Retrying…" |
| 11 | **API rate limiting on upload** | HTTP 429 response with `Retry-After` header | Uploads delayed | Honour `Retry-After` header, queue remaining uploads | "Uploads temporarily paused. Will resume shortly." |
| 12 | **Signed URL expired before upload completes** | HTTP 403 from GCS | Upload fails | Request new signed URL from API, restart upload (resumable URI invalid) | Silent retry — user sees upload progress reset for that chunk |

### 8.3 Processing Phase Exceptions

| # | Scenario | Detection Method | User Impact | Recovery Strategy | User Communication |
|---|----------|-----------------|-------------|-------------------|-------------------|
| 13 | **Google STT API fails (500/503)** | HTTP error response from STT API | Transcript delayed | Retry 3× with backoff → fallback to Whisper API → if both fail, mark chunk as failed | "Processing is taking longer than usual. We're working on it." |
| 14 | **Google STT API rate limited** | HTTP 429 from STT | Transcript delayed | Queue with delayed execution; spread jobs over time | Same as #13 |
| 15 | **STT returns empty / gibberish transcript** | Confidence score < 0.3 OR word count < 10 for a 15-min chunk | Low-quality transcript | Re-process with Whisper; if also poor, mark as low-confidence and flag for user review | "This segment may have poor audio quality. Please review the transcript." |
| 16 | **Gemini API fails** | HTTP error or timeout from Gemini API | No AI summary generated | Retry 3× → try simpler prompt → mark as failed | "We couldn't generate study notes right now. Your transcript is still available. Tap to retry." |
| 17 | **Gemini returns malformed output** | JSON parse failure or missing required fields | Summary not usable | Retry with stricter prompt + output schema enforcement. Max 3 retries. | Same as #16 |
| 18 | **Internet drops during processing** | Workers lose connection to external APIs | Processing stalls | BullMQ auto-retries failed jobs. Job timeout = 5 min; after timeout, re-queued. | "Processing paused. Will resume automatically." |
| 19 | **Partial transcript failure (some chunks fail, others succeed)** | `processed_chunks < total_chunks` after all STT jobs complete | Incomplete transcript with gaps | Assemble available chunks with gap markers. Allow user to re-trigger failed chunks individually. | "Your transcript is mostly complete. 2 segments couldn't be processed. [Retry Failed Segments]" |
| 20 | **PDF generation failure (Puppeteer crash)** | Worker process exits with non-zero code or timeout | No PDF available | Retry 3× → fallback to plain-text PDF generator (no Puppeteer) → if still fails, user can copy markdown | "PDF generation failed. Your notes are available in-app. [Retry PDF]" |

### 8.4 Authentication & Security Exceptions

| # | Scenario | Detection Method | User Impact | Recovery Strategy | User Communication |
|---|----------|-----------------|-------------|-------------------|-------------------|
| 21 | **Firebase Auth token expired** | HTTP 401 from API with `AUTH_TOKEN_EXPIRED` error code | API calls fail | Flutter `getIdToken(forceRefresh: true)` auto-refreshes. Retry original request with new token. Max 2 refresh attempts. | Silent — handled automatically |
| 22 | **Firebase Auth service down** | `getIdToken()` throws `FirebaseAuthException` | Can't authenticate, can't sync | All local operations continue. Sync paused. Token cached in secure storage for offline use. | "Unable to connect to authentication service. Your recordings are safe locally." |
| 23 | **User accesses another user's resource** | API middleware: `recording.user_id !== req.user.id` | Request blocked | Return 403. Log suspicious activity. | "You don't have permission to access this resource." |

### 8.5 Infrastructure & System Exceptions

| # | Scenario | Detection Method | User Impact | Recovery Strategy | User Communication |
|---|----------|-----------------|-------------|-------------------|-------------------|
| 24 | **Backend server downtime** | Health check failures; API returns 503 | All server-dependent operations fail | Client enters offline mode. All operations queued locally. Exponential backoff on health checks. | "Server temporarily unavailable. Your recordings are safe. We'll sync when the service is restored." |
| 25 | **PostgreSQL database down** | Connection pool errors; queries timeout | All API endpoints fail | Cloud SQL auto-restart + replica failover. API returns 503 to clients. | Same as #24 (client sees it as server downtime) |
| 26 | **Redis down** | BullMQ connection errors | Job queue stalls; no new processing | Redis Sentinel / auto-restart. API still accepts uploads (writes to PG); processing resumes when Redis recovers. | "Processing queue temporarily paused. Your upload was received." |
| 27 | **GCS outage** | Upload failures; signed URL generation fails | Can't upload or download | Retain audio locally. Retry uploads. For downloads (PDF), serve from cache. | "Cloud storage temporarily unavailable. Your recordings are saved locally." |
| 28 | **Worker crash / OOM** | Cloud Run health check; process exit code | Processing job lost | BullMQ detects stalled job (visibility timeout) → re-queues to another worker | Silent — job retried automatically |
| 29 | **DNS resolution failure** | Socket errors on API calls | All networking fails | Treat as offline. Use cached DNS (if available). | Same as #24 |
| 30 | **TLS certificate error** | SSL handshake failure | All HTTPS calls fail | Certificate pinning override for known endpoints. Log and alert ops team. | "Secure connection failed. Please check your date/time settings and try again." |

### 8.6 Data Integrity Exceptions

| # | Scenario | Detection Method | User Impact | Recovery Strategy | User Communication |
|---|----------|-----------------|-------------|-------------------|-------------------|
| 31 | **SQLite database corruption** | `PRAGMA integrity_check` on startup; `DatabaseException` during queries | Local data may be partially lost | Restore from last known good backup (app maintains WAL snapshots). Re-sync from server. | "Local data was repaired. Re-syncing from server…" |
| 32 | **Sync conflict — divergent data** | `updated_at` mismatch during sync | User may lose one version of an edit | LWW with conflict log. User can review conflicts in Settings → Sync History. | "A sync conflict was detected. The most recent version was kept. [View Details]" |
| 33 | **Orphaned audio files (no DB record)** | Periodic scan: files in chunks dir without matching SQLite record | Wasted storage | Cleanup job: if file is > 24h old and has no record, delete. | Silent background cleanup |

---

## 9. Scalability Considerations

### 9.1 Horizontal Scaling Architecture

```mermaid
flowchart TB
    subgraph "Auto-Scaling (Cloud Run)"
        LB["Cloud Load Balancer<br/>(HTTPS, global)"]
        LB --> API_GROUP["API Instances<br/>(min: 1, max: 50)<br/>Scale on: CPU > 60%<br/>or concurrent requests > 80"]
        LB --> WORKER_GROUP["Worker Instances<br/>(min: 0, max: 30)<br/>Scale on: queue depth"]
    end

    subgraph "Stateless Design"
        note1["✅ No server-side sessions"]
        note2["✅ JWT auth (Firebase tokens)"]
        note3["✅ Shared-nothing architecture"]
        note4["✅ All state in PG / Redis / GCS"]
    end
```

### 9.2 Capacity Planning

| Metric                         | Current Target (MVP)  | Scale Target (Year 1) | Scale Target (Year 3) |
| ------------------------------ | --------------------- | ---------------------- | ---------------------- |
| Concurrent users               | 100                   | 10,000                 | 100,000                |
| Daily recordings                | 50                    | 5,000                  | 50,000                 |
| Avg recording duration          | 60 min                | 60 min                 | 60 min                 |
| Daily audio upload volume       | 3 GB                  | 300 GB                 | 3 TB                   |
| Daily STT processing minutes    | 50 hours              | 5,000 hours            | 50,000 hours           |
| API requests/second (peak)      | 10                    | 500                    | 5,000                  |
| Database size (PostgreSQL)      | 1 GB                  | 100 GB                 | 2 TB                   |
| GCS storage (live audio)        | 10 GB                 | 500 GB                 | 5 TB                   |
| GCS storage (PDFs, permanent)   | 1 GB                  | 200 GB                 | 5 TB                   |

### 9.3 CDN Strategy

| Asset Type       | CDN Behaviour                                | Cache TTL       |
| ---------------- | -------------------------------------------- | --------------- |
| PDFs             | Cached at edge; served via signed CDN URL    | 7 days          |
| App assets       | Versioned; immutable caching                 | 365 days        |
| API responses    | Not cached (dynamic, user-specific)          | No cache        |
| Audio (temporary)| Not CDN'd (private, short-lived)             | Not applicable  |

### 9.4 Database Optimisation

| Strategy                        | Implementation                                                          |
| ------------------------------- | ----------------------------------------------------------------------- |
| **Connection pooling**          | PgBouncer in front of Cloud SQL; pool size = 20 per API instance        |
| **Read replicas**               | 1 read replica for dashboard/list queries; writes to primary only       |
| **Partitioning**                | `recordings` table partitioned by `RANGE (recorded_at)` — monthly       |
| **Archival**                    | Recordings older than 2 years → archive table (cold storage)            |
| **Query optimisation**          | All queries use parameterised prepared statements; `EXPLAIN ANALYZE` in CI |
| **Vacuum**                      | `autovacuum` enabled; custom schedule for high-churn tables (`chunks`)  |

### 9.5 Caching Strategy

```mermaid
flowchart LR
    subgraph "Cache Layers"
        L1["L1: In-Memory (LRU)<br/>Per API instance<br/>TTL: 60 seconds<br/>- User profile<br/>- Feature flags"]
        L2["L2: Redis<br/>Shared across instances<br/>TTL: 5-30 minutes<br/>- Subject lists<br/>- Recording metadata<br/>- Processing status"]
        L3["L3: CDN Edge<br/>Global<br/>TTL: variable<br/>- PDF files<br/>- Static assets"]
    end

    L1 --> L2 --> L3
```

**Cache invalidation:**
- **User edits** (recording title, subject): Invalidate L1 + L2 key for that user.
- **Processing status changes**: Worker publishes Redis `PUBLISH` event → API instances subscribe → invalidate L1.
- **PDF regeneration**: New version uploaded to GCS → CDN cache purged for that URL.

---

## 10. Monitoring & Observability

### 10.1 Observability Architecture

```mermaid
flowchart TB
    subgraph "Data Sources"
        APP["Flutter App<br/>(Crashlytics + Analytics)"]
        API["Backend API<br/>(Pino structured logs)"]
        WORKERS["Workers<br/>(Pino structured logs)"]
        INFRA["Infrastructure<br/>(Cloud Run metrics)"]
    end

    subgraph "Collection"
        CL["Google Cloud Logging"]
        CM["Google Cloud Monitoring"]
        CT["Google Cloud Trace"]
        CRASH["Firebase Crashlytics"]
        GA["Firebase Analytics"]
    end

    subgraph "Alerting"
        ALERT["Cloud Alerting Policies"]
        PD["PagerDuty / Opsgenie"]
        SLACK["Slack #lecto-alerts"]
    end

    subgraph "Dashboards"
        DASH["Cloud Monitoring Dashboards"]
        GRAFANA["Grafana (optional)"]
    end

    APP --> CRASH
    APP --> GA
    API --> CL
    API --> CT
    WORKERS --> CL
    INFRA --> CM

    CL --> DASH
    CM --> DASH
    CM --> ALERT
    ALERT --> PD
    ALERT --> SLACK
    CT --> DASH
```

### 10.2 Logging Strategy

**Structured log format (all services):**

```json
{
  "timestamp": "2026-07-07T01:00:00.000Z",
  "level": "info",
  "service": "api",
  "requestId": "req_abc123",
  "userId": "usr_xyz789",
  "method": "POST",
  "path": "/api/v1/chunks",
  "statusCode": 201,
  "durationMs": 342,
  "message": "Chunk uploaded successfully",
  "metadata": {
    "recordingId": "rec_123",
    "chunkIndex": 3,
    "fileSizeBytes": 15728640
  }
}
```

**Log levels and usage:**

| Level     | Usage                                                                 | Example                              |
| --------- | --------------------------------------------------------------------- | ------------------------------------ |
| `fatal`   | Process is about to crash                                             | Unhandled exception in worker        |
| `error`   | Operation failed; needs investigation                                 | STT API returned 500                 |
| `warn`    | Unexpected but handled situation                                      | Whisper fallback triggered           |
| `info`    | Normal operation milestones                                           | Chunk uploaded, transcript assembled |
| `debug`   | Diagnostic detail (disabled in production)                            | Request payload, query plans         |
| `trace`   | Extremely verbose (never in production)                               | Function entry/exit                  |

**Sensitive data handling:** User audio content, transcript text, and personal information are **never** logged. Only IDs, sizes, durations, and status codes appear in logs.

### 10.3 Key Metrics & Alerts

| Metric                                 | Source            | Alert Threshold                       | Severity |
| -------------------------------------- | ----------------- | ------------------------------------- | -------- |
| API error rate (5xx)                   | Cloud Monitoring  | > 5% of requests in 5-min window      | Critical |
| API latency (p99)                      | Cloud Trace       | > 2000 ms                            | Warning  |
| STT job failure rate                   | BullMQ metrics    | > 10% of jobs in 1 hour               | Critical |
| AI summary failure rate                | BullMQ metrics    | > 20% of jobs in 1 hour               | Warning  |
| Queue depth (STT)                      | Redis / BullMQ    | > 500 pending jobs                     | Warning  |
| Queue depth (STT)                      | Redis / BullMQ    | > 2000 pending jobs                    | Critical |
| Database connection pool exhaustion    | PgBouncer         | Available connections < 5              | Critical |
| GCS upload error rate                  | Cloud Monitoring  | > 3% of uploads in 15 min             | Warning  |
| Cloud Run instance count               | Cloud Monitoring  | > 40 instances (nearing max)           | Warning  |
| Firebase Auth errors                   | Firebase Console  | > 50 errors in 5 min                  | Warning  |
| App crash rate (mobile)                | Crashlytics       | > 1% crash-free users drop            | Critical |
| Recording recovery events             | App Analytics     | > 10 recoveries in 1 hour             | Warning  |

### 10.4 Analytics Events (Mobile App)

| Event Name                | Properties                                           | Purpose                            |
| ------------------------- | ---------------------------------------------------- | ---------------------------------- |
| `recording_started`       | `{ subjectId, language }`                            | Track recording frequency          |
| `recording_completed`     | `{ durationMin, chunkCount, wasOffline }`            | Track recording patterns           |
| `recording_recovered`     | `{ recoverType, chunksRecovered }`                   | Monitor stability                  |
| `upload_started`          | `{ chunkCount, totalSizeMB }`                        | Track upload patterns              |
| `upload_completed`        | `{ durationSec, wasResumed }`                        | Track upload reliability           |
| `transcript_viewed`       | `{ recordingId, hasGaps }`                           | Track feature usage                |
| `summary_viewed`          | `{ recordingId }`                                    | Track feature usage                |
| `pdf_downloaded`          | `{ recordingId, fileSizeMB }`                        | Track export usage                 |
| `summary_regenerated`     | `{ recordingId, reason }`                            | Track AI quality issues            |
| `storage_warning_shown`   | `{ availableStorageMB, lectoUsageMB }`               | Monitor storage pressure           |
| `sync_completed`          | `{ itemsSynced, conflictsResolved, durationSec }`    | Track sync health                  |
| `offline_session`         | `{ durationMin, actionsPerformed }`                  | Understand offline usage           |

---

## 11. Security Architecture

### 11.1 Security Layers

```mermaid
flowchart TD
    subgraph "Transport Security"
        TLS["TLS 1.3<br/>(all connections)"]
        CERT["Certificate Pinning<br/>(mobile app → API)"]
    end

    subgraph "Authentication"
        FB["Firebase Auth<br/>(ID tokens, 1h expiry)"]
        VERIFY["Server-side token<br/>verification on every request"]
    end

    subgraph "Authorization"
        OWNER["Resource ownership check<br/>(user can only access own data)"]
        RBAC["Role-based access<br/>(future: shared notebooks)"]
    end

    subgraph "Data Protection"
        ENCRYPT_REST["Encryption at rest<br/>(GCS, Cloud SQL, device)"]
        ENCRYPT_TRANSIT["Encryption in transit<br/>(TLS)"]
        PII["PII minimisation<br/>(no unnecessary personal data)"]
    end

    subgraph "API Security"
        RATE["Rate limiting"]
        CORS_BLOCK["CORS (mobile only)"]
        HELMET["Security headers<br/>(Helmet/fastify-helmet)"]
        INPUT["Input validation<br/>(Zod schemas on all routes)"]
    end

    TLS --> FB --> OWNER --> ENCRYPT_REST
    CERT --> VERIFY --> RBAC --> ENCRYPT_TRANSIT
    RATE --> INPUT
```

### 11.2 Data Encryption

| Data                    | At Rest                                            | In Transit         |
| ----------------------- | -------------------------------------------------- | ------------------- |
| Audio chunks (device)   | OS-level encryption (iOS Keychain, Android Keystore) | TLS 1.3 to GCS    |
| Audio chunks (GCS)      | Google-managed AES-256                             | TLS 1.3            |
| Database (Cloud SQL)    | Google-managed AES-256                             | TLS 1.3            |
| SQLite (device)         | `sqlcipher` with user-derived key                  | N/A (local)        |
| Firebase tokens         | Secure Storage (flutter_secure_storage)            | TLS 1.3            |
| PDF files (GCS)         | Google-managed AES-256                             | Signed HTTPS URLs  |

### 11.3 API Security Checklist

- [x] All endpoints require authenticated Firebase ID token (except `/health`)
- [x] Resource ownership verified on every data access (no IDOR)
- [x] Input validated with Zod schemas — reject unknown fields
- [x] Rate limiting per IP and per user
- [x] No sensitive data in URL query parameters
- [x] No sensitive data in logs
- [x] CORS configured for known origins only
- [x] File upload size limited (max 50 MB per chunk)
- [x] Content-Type validation on uploads (audio/* only)
- [x] SQL injection prevented via parameterised queries (Drizzle ORM)
- [x] XSS not applicable (API-only, no HTML rendering to clients)
- [x] Dependency vulnerability scanning in CI (npm audit, Snyk)

---

## 12. Appendices

### Appendix A: Environment Variables

```bash
# === Server ===
NODE_ENV=production
PORT=8080
API_VERSION=v1
LOG_LEVEL=info

# === Database ===
DATABASE_URL=postgresql://user:pass@host:5432/lecto?sslmode=require
DATABASE_POOL_MIN=2
DATABASE_POOL_MAX=20

# === Redis ===
REDIS_URL=redis://host:6379

# === Google Cloud ===
GCP_PROJECT_ID=lecto-prod
GCS_AUDIO_BUCKET=lecto-audio-chunks
GCS_PDF_BUCKET=lecto-pdfs
GOOGLE_APPLICATION_CREDENTIALS=/secrets/gcp-sa-key.json

# === Firebase ===
FIREBASE_PROJECT_ID=lecto-prod

# === Google Cloud Speech-to-Text ===
GOOGLE_STT_ENABLED=true

# === OpenAI (Whisper fallback) ===
OPENAI_API_KEY=sk-...
WHISPER_MODEL=whisper-1

# === Google Gemini ===
GEMINI_API_KEY=...
GEMINI_MODEL=gemini-2.0-pro

# === Rate Limiting ===
RATE_LIMIT_GLOBAL_MAX=100
RATE_LIMIT_GLOBAL_WINDOW_MS=60000
```

### Appendix B: Docker Configuration

```dockerfile
# Dockerfile (backend-api)
FROM node:20-slim AS base
RUN apt-get update && apt-get install -y \
    chromium \
    fonts-liberation \
    --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium

WORKDIR /app

# Dependencies
COPY package.json package-lock.json ./
RUN npm ci --production

# Source
COPY dist/ ./dist/

EXPOSE 8080
CMD ["node", "dist/index.js"]
```

```yaml
# docker-compose.yml (local development)
version: '3.9'
services:
  api:
    build: .
    ports: ['8080:8080']
    env_file: .env
    depends_on: [postgres, redis]
    volumes: ['./src:/app/src']

  worker:
    build: .
    command: ['node', 'dist/workers/index.js']
    env_file: .env
    depends_on: [postgres, redis]

  postgres:
    image: postgres:16
    environment:
      POSTGRES_DB: lecto
      POSTGRES_USER: lecto
      POSTGRES_PASSWORD: localdev
    ports: ['5432:5432']
    volumes: ['pgdata:/var/lib/postgresql/data']

  redis:
    image: redis:7-alpine
    ports: ['6379:6379']

volumes:
  pgdata:
```

### Appendix C: Deployment Architecture

```mermaid
flowchart TB
    subgraph "CI/CD (GitHub Actions)"
        PR["Pull Request"] --> LINT["Lint + Test"]
        LINT --> BUILD["Docker Build"]
        BUILD --> PUSH["Push to Artifact Registry"]
        PUSH --> DEPLOY_STG["Deploy to Staging<br/>(Cloud Run)"]
        DEPLOY_STG --> E2E["E2E Tests"]
        E2E --> APPROVE["Manual Approval"]
        APPROVE --> DEPLOY_PROD["Deploy to Production<br/>(Cloud Run, canary 10%)"]
        DEPLOY_PROD --> MONITOR["Monitor 15 min"]
        MONITOR --> FULL["Full rollout (100%)"]
    end

    subgraph "Production (Google Cloud)"
        CR_API["Cloud Run: API<br/>(min 1, max 50)"]
        CR_WORKER["Cloud Run: Workers<br/>(min 0, max 30)"]
        CSQL["Cloud SQL: PostgreSQL 16<br/>(HA, auto-backup)"]
        MR["Memorystore: Redis 7"]
        GCS_B["GCS Buckets"]
    end

    FULL --> CR_API
    FULL --> CR_WORKER
```

### Appendix D: Glossary

| Term              | Definition                                                                            |
| ----------------- | ------------------------------------------------------------------------------------- |
| **Chunk**         | A segment of audio (10-20 min) split from a continuous recording for pipeline processing |
| **STT**           | Speech-to-Text — the process of converting audio into text                            |
| **LWW**           | Last-Write-Wins — a conflict resolution strategy where the most recent write prevails |
| **BLoC**          | Business Logic Component — a Flutter state management pattern                         |
| **WAL**           | Write-Ahead Log — SQLite's journaling mode for crash-safe writes                      |
| **Resumable Upload** | A GCS upload protocol that allows continuing from the last uploaded byte after interruption |
| **Pipeline**      | The sequential processing chain: Upload → STT → Assembly → AI → PDF → Cleanup        |
| **Sync Engine**   | The mobile app component responsible for bidirectional data synchronization            |
| **Idempotent**    | An operation that produces the same result regardless of how many times it is executed |
| **Gap Marker**    | A placeholder in the transcript indicating a chunk that could not be transcribed      |

---

> **Document End** — This TAD provides the complete architectural blueprint for Lecto. All diagrams, schemas, and specifications are ready for development team implementation.
