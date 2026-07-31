<div align="center">

<!-- LOGO PLACEHOLDER — Replace with actual logo when available -->
<!-- <img src="docs-and-assets/branding/lecto-logo.png" alt="Lecto Logo" width="200"> -->

# 📖 Lecto

### _Never miss a word. Every lecture, perfectly captured._

**Record lectures. Generate transcripts. Study smarter.**

[![Build Status](https://img.shields.io/badge/build-passing-brightgreen?style=flat-square)](https://github.com/your-org/lecto/actions)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue?style=flat-square)](LICENSE)
[![Version](https://img.shields.io/badge/version-1.0.0--beta-orange?style=flat-square)](#)
[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev)
[![Node.js](https://img.shields.io/badge/Node.js-20.x-339933?style=flat-square&logo=nodedotjs&logoColor=white)](https://nodejs.org)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen?style=flat-square)](CONTRIBUTING.md)

---

[Features](#-v1-features) · [Tech Stack](#-tech-stack) · [Getting Started](#-getting-started) · [Documentation](#-documentation) · [Roadmap](#-roadmap) · [Contributing](#-contributing)

</div>

<br/>

## 🤔 What is Lecto?

### The Problem

Students lose **40–60%** of lecture content within 24 hours of hearing it. Manually taking notes means splitting attention between listening and writing, resulting in fragmented, incomplete notes. Existing recording apps give you a raw audio file — but who has time to re-listen to a 90-minute lecture?

### The Solution

**Lecto** is a mobile-first application that records lectures in real-time, automatically generates accurate transcripts using AI, and transforms them into **structured, study-ready notes** — complete with summaries, key points, and exportable PDFs. It works offline, organizes content by subject, and gives students back the one thing they never have enough of: _time_.

### ✨ Key Features at a Glance

| | Feature | Description |
|---|---|---|
| 🎤 | **Smart Recording** | Intelligent audio capture with automatic chunking for long lectures |
| 📝 | **AI Transcription** | Accurate, punctuated transcripts generated from your recordings |
| 🧠 | **Study Notes** | AI-structured summaries, key takeaways, and concept breakdowns |
| 📁 | **Subject Organization** | Keep everything tidy — organized by course, subject, and date |
| 📴 | **Offline-First** | Record and review without an internet connection |
| 📄 | **PDF Export** | Generate beautifully formatted PDFs for printing or sharing |

---

## 🚀 V1 Features

### 🎤 Smart Recording

> Effortless audio capture built for the classroom.

- **One-tap recording** — start capturing instantly with a single press
- **Automatic chunking** — long lectures are intelligently split into manageable segments
- **Background recording** — keep recording even when you switch apps or lock your screen
- **Audio quality indicators** — real-time feedback so you know you're capturing clearly
- **Pause & resume** — seamlessly handle breaks without splitting your recording

### 📝 AI-Powered Transcript Generation

> From spoken words to searchable text, automatically.

- **High-accuracy transcription** powered by state-of-the-art speech-to-text models
- **Speaker awareness** — distinguish between lecturer and Q&A segments
- **Punctuation & formatting** — clean, readable transcripts, not a wall of text
- **Timestamped segments** — jump to any part of the lecture from the transcript
- **Edit & correct** — refine transcripts inline for perfect accuracy

### 🧠 Intelligent Summary & Structured Notes

> AI doesn't just transcribe — it _understands_.

- **Auto-generated summaries** — concise overviews of each lecture
- **Key points extraction** — the important takeaways, highlighted
- **Concept breakdowns** — complex topics explained in structured sections
- **Bullet-point notes** — study-ready notes formatted for quick review
- **Keyword tagging** — automatic topic detection and tagging

### 📁 Subject-Based Organization

> Every lecture, right where you expect it.

- **Create subjects & courses** — mirror your real class schedule
- **Auto-sort by date** — chronological organization within each subject
- **Search across everything** — full-text search across all transcripts and notes
- **Favorites & pinning** — quick access to your most important recordings

### 📴 Offline-First Architecture

> No Wi-Fi in the lecture hall? No problem.

- **Record without internet** — full recording functionality offline
- **Local-first storage** — your data lives on your device first
- **Smart sync** — automatic background upload when connectivity returns
- **Queue management** — pending transcriptions are queued and processed in order

### 📄 Beautiful PDF Export

> From lecture to polished document in one tap.

- **Formatted transcripts** — clean, professional PDF output
- **Structured notes** — summaries and key points in a print-ready layout
- **Custom branding** — add your name, course info, and date
- **Share anywhere** — export to email, cloud storage, or messaging apps

---

## 🛠️ Tech Stack

| Layer | Technology | Purpose |
|---|---|---|
| **Mobile App** | Flutter / Dart | Cross-platform mobile application (iOS & Android) |
| **Backend API** | Node.js / Express | RESTful API server, business logic, AI orchestration |
| **Database** | PostgreSQL | Primary relational data store |
| **Cache** | Redis | Session management, job queues, caching |
| **AI / ML** | OpenAI Whisper API | Speech-to-text transcription |
| **AI / ML** | GPT-4o / Claude | Summary generation, note structuring |
| **Object Storage** | AWS S3 / Cloudflare R2 | Audio file storage |
| **Auth** | Firebase Auth / JWT | User authentication & authorization |
| **Admin Dashboard** | React / Next.js | Internal admin web interface |
| **Marketing Site** | Astro / Tailwind CSS | Public-facing landing page |
| **Infrastructure** | Docker / Terraform | Containerization & infrastructure-as-code |
| **CI/CD** | GitHub Actions | Automated testing, building, and deployment |
| **Monitoring** | Sentry / Grafana | Error tracking & observability |

---

## 📂 Project Structure

This is a **monorepo** containing all Lecto components:

```
Lecto/
│
├── 📱 mobile-app/              # Flutter/Dart mobile application
│   ├── lib/                    #   Application source code
│   ├── test/                   #   Unit & widget tests
│   ├── android/                #   Android-specific configuration
│   ├── ios/                    #   iOS-specific configuration
│   └── pubspec.yaml            #   Dart dependencies
│
├── ⚙️ backend-api/              # Node.js backend API
│   ├── src/                    #   Server source code
│   │   ├── routes/             #     API route handlers
│   │   ├── services/           #     Business logic & AI integration
│   │   ├── models/             #     Database models
│   │   └── middleware/         #     Auth, validation, error handling
│   ├── tests/                  #   API tests
│   └── package.json            #   Node.js dependencies
│
├── 🖥️ admin-dashboard/          # Admin web dashboard (React)
│   ├── src/                    #   Dashboard source code
│   └── package.json            #   Dependencies
│
├── 🌐 marketing-website/        # Marketing/landing page
│   ├── src/                    #   Website source code
│   └── package.json            #   Dependencies
│
├── 🏗️ infrastructure/           # Infrastructure & DevOps
│   ├── docker/                 #   Dockerfiles & compose configs
│   ├── terraform/              #   IaC definitions
│   ├── k8s/                    #   Kubernetes manifests (if applicable)
│   └── .github/workflows/     #   CI/CD pipeline definitions
│
├── 📚 docs-and-assets/          # Documentation & branding
│   ├── api-docs/               #   API documentation (OpenAPI/Swagger)
│   ├── branding/               #   Logos, icons, brand guidelines
│   ├── PRD.md                  #   Product Requirements Document
│   ├── TAD.md                  #   Technical Architecture Document
│   ├── SECURITY.md             #   Security & Access Control
│   ├── FRONTEND_SPEC.md        #   Frontend Specification
│   ├── FEATURE_TICKETS.md      #   Feature Tickets & Issue Tracker
│   └── DATA_FLOW.md            #   Data Flow & Pipeline Document
│
└── 📄 README.md                 # ← You are here
```

| Directory | Description |
|---|---|
| `mobile-app/` | The core Flutter application — recording UI, local storage, offline sync, and PDF export |
| `backend-api/` | Node.js API handling authentication, audio processing pipeline, AI transcription & summarization |
| `admin-dashboard/` | Internal React dashboard for user management, analytics, and system monitoring |
| `marketing-website/` | Public-facing landing page showcasing features, pricing, and download links |
| `infrastructure/` | Docker configurations, Terraform IaC, CI/CD workflows, and deployment scripts |
| `docs-and-assets/` | All project documentation, API specs, branding assets, and architectural documents |

---

## 🏁 Getting Started

### Prerequisites

Ensure the following are installed on your development machine:

| Tool | Version | Installation |
|---|---|---|
| **Flutter SDK** | ≥ 3.22.x | [flutter.dev/docs/get-started](https://flutter.dev/docs/get-started/install) |
| **Dart SDK** | ≥ 3.4.x | Bundled with Flutter |
| **Node.js** | ≥ 20.x LTS | [nodejs.org](https://nodejs.org) |
| **npm / yarn** | ≥ 10.x / 1.22.x | Bundled with Node.js |
| **PostgreSQL** | ≥ 15.x | [postgresql.org](https://www.postgresql.org/download/) |
| **Redis** | ≥ 7.x | [redis.io](https://redis.io/download) |
| **Docker** | ≥ 24.x | [docker.com](https://www.docker.com/get-started) |
| **Git** | ≥ 2.40.x | [git-scm.com](https://git-scm.com) |

### 1. Clone the Repository

```bash
git clone https://github.com/your-org/lecto.git
cd lecto
```

### 2. Set Up the Mobile App

```bash
cd mobile-app

# Install dependencies
flutter pub get

# Run on a connected device or emulator
flutter run
```

### 3. Set Up the Backend API

```bash
cd backend-api

# Install dependencies
npm install

# Copy environment template and configure
cp .env.example .env
# Edit .env with your database credentials and API keys

# Run database migrations
npm run db:migrate

# Start the development server
npm run dev
```

### 4. Set Up the Admin Dashboard

```bash
cd admin-dashboard

# Install dependencies
npm install

# Start the development server
npm run dev
```

### 5. Set Up the Marketing Website

```bash
cd marketing-website

# Install dependencies
npm install

# Start the development server
npm run dev
```

### 🐳 Quick Start with Docker (Recommended)

Spin up the entire backend stack in one command:

```bash
cd infrastructure/docker

# Build and start all services
docker compose up --build

# Services will be available at:
#   Backend API       → http://localhost:3000
#   Admin Dashboard   → http://localhost:3001
#   PostgreSQL        → localhost:5432
#   Redis             → localhost:6379
```

### 🔐 Environment Variables

Create a `.env` file in `backend-api/` with the following variables:

```env
# ── Server ──────────────────────────────
PORT=3000
NODE_ENV=development

# ── Database ────────────────────────────
DATABASE_URL=postgresql://user:password@localhost:5432/lecto_db

# ── Redis ───────────────────────────────
REDIS_URL=redis://localhost:6379

# ── Authentication ──────────────────────
JWT_SECRET=your-super-secret-jwt-key
FIREBASE_PROJECT_ID=your-firebase-project-id
FIREBASE_PRIVATE_KEY=your-firebase-private-key

# ── AI / Transcription ─────────────────
OPENAI_API_KEY=sk-your-openai-api-key

# ── Object Storage ─────────────────────
AWS_S3_BUCKET=lecto-audio-uploads
AWS_ACCESS_KEY_ID=your-access-key
AWS_SECRET_ACCESS_KEY=your-secret-key
AWS_REGION=us-east-1

# ── Monitoring ──────────────────────────
SENTRY_DSN=https://your-sentry-dsn
```

> [!CAUTION]
> Never commit `.env` files to version control. The `.gitignore` is pre-configured to exclude them.

---

## 📚 Documentation

All project documentation lives in the [`docs-and-assets/`](docs-and-assets/) directory:

| Document | Description | Link |
|---|---|---|
| 📋 **PRD** | Product Requirements Document — features, user stories, acceptance criteria | [`PRD.md`](docs-and-assets/PRD.md) |
| 🏗️ **TAD** | Technical Architecture Document — system design, infrastructure, data models | [`TAD.md`](docs-and-assets/TAD.md) |
| 🔒 **Security** | Security & access control policies, authentication flows, data protection | [`SECURITY.md`](docs-and-assets/SECURITY.md) |
| 🎨 **Frontend Spec** | Frontend specification — UI/UX guidelines, component library, design tokens | [`FRONTEND_SPEC.md`](docs-and-assets/FRONTEND_SPEC.md) |
| 🎫 **Feature Tickets** | Feature ticket list — development tasks, priorities, and status tracking | [`FEATURE_TICKETS.md`](docs-and-assets/FEATURE_TICKETS.md) |
| 🔀 **Data Flow** | Data flow & pipeline document — audio processing, transcription pipeline | [`DATA_FLOW.md`](docs-and-assets/DATA_FLOW.md) |
| 📡 **API Docs** | API documentation — endpoint reference, request/response schemas | [`api-docs/`](docs-and-assets/api-docs/) |
| 🎨 **Branding** | Logos, icons, color palette, and brand guidelines | [`branding/`](docs-and-assets/branding/) |

---

## 🏛️ Architecture Overview

```mermaid
graph TB
    subgraph Client["📱 Mobile App (Flutter)"]
        UI["UI Layer"]
        LocalDB["Local Database (SQLite)"]
        Recorder["Audio Recorder"]
    end

    subgraph Backend["⚙️ Backend API (Node.js)"]
        API["REST API"]
        Auth["Auth Service"]
        AudioSvc["Audio Processing"]
        AISvc["AI Service"]
        Queue["Job Queue (Redis)"]
    end

    subgraph AI["🤖 AI Services"]
        Whisper["OpenAI Whisper"]
        LLM["GPT-4o / Claude"]
    end

    subgraph Storage["💾 Storage"]
        DB["PostgreSQL"]
        S3["Object Storage (S3)"]
        Cache["Redis Cache"]
    end

    UI --> Recorder
    Recorder --> LocalDB
    UI --> API
    LocalDB -->|"Sync when online"| API

    API --> Auth
    API --> AudioSvc
    API --> AISvc
    API --> Queue

    AudioSvc -->|"Upload audio"| S3
    AISvc -->|"Transcribe"| Whisper
    AISvc -->|"Summarize"| LLM

    Queue --> Cache
    API --> DB

    style Client fill:#E3F2FD,stroke:#1565C0,color:#000
    style Backend fill:#FFF3E0,stroke:#E65100,color:#000
    style AI fill:#F3E5F5,stroke:#6A1B9A,color:#000
    style Storage fill:#E8F5E9,stroke:#2E7D32,color:#000
```

### How It Works

```mermaid
sequenceDiagram
    participant S as 📱 Student
    participant App as Lecto App
    participant API as Backend API
    participant AI as AI Services
    participant Store as Storage

    S->>App: Tap "Record"
    App->>App: Capture audio locally
    S->>App: Tap "Stop"
    App->>App: Save to local DB (offline-ready)

    App->>API: Upload audio chunks
    API->>Store: Store audio in S3
    API->>AI: Send to Whisper (transcription)
    AI-->>API: Return transcript
    API->>AI: Send to LLM (summarization)
    AI-->>API: Return structured notes
    API-->>App: Deliver transcript + notes
    App->>App: Cache locally for offline access
    App-->>S: View notes, export PDF ✅
```

---

## 🗺️ Roadmap

### ✅ V1 — Foundation (Current)

- [x] Audio recording with automatic chunking
- [x] AI-powered transcript generation
- [x] Intelligent summaries & structured notes
- [x] Subject-based organization
- [x] Offline-first architecture
- [x] PDF export
- [x] User authentication
- [x] Basic admin dashboard

### 🔮 V2 — Enhance (Planned)

- [ ] **📸 Image & Slide Capture** — photograph whiteboard/slides and attach to recordings
- [ ] **🔍 Semantic Search** — search across all notes using natural language queries
- [ ] **🌍 Multi-language Support** — transcription and notes in 20+ languages
- [ ] **👥 Collaborative Notes** — share notes with classmates, co-edit in real time
- [ ] **📊 Study Analytics** — track study time, review frequency, knowledge gaps
- [ ] **🔔 Smart Reminders** — spaced repetition reminders based on note content
- [ ] **🎯 Quiz Generation** — auto-generate practice questions from lecture content
- [ ] **📅 Calendar Integration** — sync with university timetable / Google Calendar
- [ ] **💬 In-app Chat** — ask questions about your notes using an AI tutor
- [ ] **🖥️ Web App** — access notes from any browser on desktop

### 🚀 V3 — Scale (Future)

- [ ] **🏫 University Partnerships** — institutional licensing and LMS integrations
- [ ] **♿ Accessibility** — live captioning, screen reader optimization, high-contrast mode
- [ ] **🔗 Integrations** — Notion, Google Drive, OneDrive, Evernote export
- [ ] **📈 Advanced Analytics** — professor-facing dashboards, engagement metrics
- [ ] **🎓 Study Groups** — group workspaces with shared recordings and notes

---

## 🤝 Contributing

We'd love your help making Lecto better! Here's how to get started:

### Quick Steps

1. **Fork** the repository
2. **Create** a feature branch: `git checkout -b feat/amazing-feature`
3. **Commit** your changes: `git commit -m "feat: add amazing feature"`
4. **Push** to the branch: `git push origin feat/amazing-feature`
5. **Open** a Pull Request

### Guidelines

- Follow the existing code style and conventions
- Write meaningful commit messages using [Conventional Commits](https://www.conventionalcommits.org/)
- Add tests for new features and bug fixes
- Update documentation when changing public APIs
- Keep PRs focused — one feature or fix per PR

### Commit Convention

```
feat:     New feature
fix:      Bug fix
docs:     Documentation changes
style:    Code style changes (formatting, semicolons, etc.)
refactor: Code refactoring (no feature or fix)
test:     Adding or updating tests
chore:    Build process, tooling, or dependency updates
```

> [!TIP]
> Not sure where to start? Look for issues labeled [`good first issue`](https://github.com/your-org/lecto/labels/good%20first%20issue) or [`help wanted`](https://github.com/your-org/lecto/labels/help%20wanted).

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

```
MIT License

Copyright (c) 2026 Lecto

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

---

<div align="center">

**Built with ❤️ for students everywhere.**

[⬆ Back to Top](#-lecto)

</div>
