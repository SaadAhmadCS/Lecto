# 🔐 Lecto — Security & Access Control Document

> **Version**: 1.0.0
> **Last Updated**: 2026-07-07
> **Classification**: INTERNAL — CONFIDENTIAL
> **Owner**: Lecto Security Team
> **Review Cycle**: Quarterly (next review: 2026-10-07)

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Threat Model Overview](#2-threat-model-overview)
3. [Authentication & Authorization](#3-authentication--authorization)
4. [Data Security](#4-data-security)
5. [API Security](#5-api-security)
6. [Privacy & Compliance](#6-privacy--compliance)
7. [Access Control Matrix (RBAC)](#7-access-control-matrix-rbac)
8. [Mobile App Security](#8-mobile-app-security)
9. [Infrastructure Security](#9-infrastructure-security)
10. [Incident Response](#10-incident-response)
11. [Audit & Monitoring](#11-audit--monitoring)
12. [Third-Party Security](#12-third-party-security)
13. [Security Checklist](#13-security-checklist)
14. [Document History](#14-document-history)

---

## 1. Executive Summary

Lecto is a mobile application that records lectures, auto-generates transcripts via AI, and produces structured study notes. By its nature, the platform handles **highly sensitive data**:

| Data Type | Sensitivity | Risk |
|---|---|---|
| Audio recordings of lectures | **High** | Professor's intellectual property, copyrighted material |
| Transcripts | **High** | May contain PII, proprietary academic content |
| Study notes | **Medium** | Derived content, user's personal study patterns |
| User account data | **High** | Email, name, institution, payment info |
| Usage analytics | **Low–Medium** | Study habits, session duration, feature usage |

This document defines the complete security architecture, policies, and procedures that govern how Lecto protects this data across all layers — from the user's device to our cloud infrastructure, and across every third-party integration.

> [!IMPORTANT]
> Every engineer, contractor, and third-party vendor with access to Lecto systems **must** read and acknowledge this document before being granted access.

---

## 2. Threat Model Overview

### 2.1 Trust Boundaries

```mermaid
graph TB
    subgraph "User Device (Untrusted)"
        A["Lecto Mobile App"]
        B["Local SQLite DB"]
        C["Audio Files on Disk"]
    end

    subgraph "Network (Untrusted)"
        D["TLS 1.3 Encrypted Channel"]
    end

    subgraph "Lecto Cloud (Trusted)"
        E["API Gateway / Load Balancer"]
        F["Auth Service"]
        G["Core API Service"]
        H["Transcription Worker"]
        I["Notes Generation Worker"]
        J["PostgreSQL Database"]
        K["Cloud Storage (Audio/Transcripts)"]
    end

    subgraph "Third-Party APIs (Semi-Trusted)"
        L["Google Cloud Speech-to-Text"]
        M["Gemini API"]
        N["Firebase Auth"]
    end

    A -->|HTTPS| D
    D -->|TLS Terminated| E
    E --> F
    E --> G
    G --> H
    G --> I
    H --> L
    I --> M
    F --> N
    G --> J
    G --> K
```

### 2.2 Primary Threat Actors

| Actor | Motivation | Capability | Priority |
|---|---|---|---|
| **Malicious student** | Access others' recordings/notes | Moderate — authenticated user | 🔴 High |
| **External attacker** | Data theft, ransomware | High — network-level | 🔴 High |
| **Compromised third-party** | Supply-chain attack | High — trusted access | 🟡 Medium |
| **Insider threat** | Data exfiltration | High — system access | 🟡 Medium |
| **Automated bot** | Account stuffing, API abuse | Moderate — scalable | 🟡 Medium |

### 2.3 STRIDE Analysis Summary

| Threat | Description | Primary Mitigation |
|---|---|---|
| **Spoofing** | Attacker impersonates a user | JWT + OAuth 2.0, MFA |
| **Tampering** | Modification of transcripts/notes in transit | TLS 1.3, HMAC integrity checks |
| **Repudiation** | User denies recording a lecture | Audit logging with tamper-evident storage |
| **Information Disclosure** | Unauthorized access to recordings | Encryption at rest + in transit, RBAC |
| **Denial of Service** | API overwhelmed with requests | Rate limiting, DDoS protection, CDN |
| **Elevation of Privilege** | Free user accesses premium features | Server-side role enforcement, JWT claims |

---

## 3. Authentication & Authorization

### 3.1 Authentication Architecture

```mermaid
sequenceDiagram
    participant U as User (Mobile App)
    participant FB as Firebase Auth
    participant API as Lecto API
    participant DB as Database

    U->>FB: 1. Login (Email/Google/Apple)
    FB-->>U: 2. Firebase ID Token (JWT)
    U->>API: 3. POST /auth/login (ID Token)
    API->>FB: 4. Verify ID Token (Admin SDK)
    FB-->>API: 5. Decoded claims (uid, email, provider)
    API->>DB: 6. Upsert user record
    DB-->>API: 7. User profile + role
    API-->>U: 8. Lecto Access Token (JWT) + Refresh Token
    Note over U,API: Subsequent requests use Lecto Access Token
    U->>API: 9. GET /lectures (Authorization: Bearer <token>)
    API->>API: 10. Verify JWT, extract user_id, check role
    API-->>U: 11. User's lectures only
```

### 3.2 Authentication Providers

| Provider | Method | Status | Notes |
|---|---|---|---|
| **Email + Password** | Firebase Auth | ✅ Required | Min 8 chars, complexity enforced |
| **Google OAuth 2.0** | Firebase Auth (Google provider) | ✅ Required | Most students use Google accounts |
| **Apple Sign In** | Firebase Auth (Apple provider) | ✅ Required | Mandatory for iOS App Store |
| **Microsoft / Edu** | Firebase Auth (Microsoft provider) | 🔜 Planned | For `.edu` institutional accounts |

### 3.3 JWT Token Strategy

#### Access Token (Short-Lived)

```json
{
  "header": {
    "alg": "RS256",
    "typ": "JWT",
    "kid": "lecto-key-2026-07"
  },
  "payload": {
    "sub": "usr_a1b2c3d4e5",
    "email": "student@university.edu",
    "role": "premium",
    "plan_tier": "pro",
    "iat": 1751846400,
    "exp": 1751847300,
    "iss": "https://api.lecto.app",
    "aud": "lecto-mobile-app",
    "jti": "tok_f6g7h8i9j0"
  }
}
```

| Parameter | Value | Rationale |
|---|---|---|
| **Algorithm** | RS256 (RSA + SHA-256) | Asymmetric — only server can sign, clients can verify |
| **Access Token TTL** | 15 minutes | Limits exposure window if token is compromised |
| **Refresh Token TTL** | 30 days | Sliding window; reset on use |
| **Token ID (`jti`)** | UUID per token | Enables revocation via deny-list |
| **Audience (`aud`)** | `lecto-mobile-app` | Prevents token misuse across services |
| **Key Rotation** | Every 90 days | Old keys remain valid for verification during grace period |

#### Token Refresh Flow

```mermaid
sequenceDiagram
    participant App as Mobile App
    participant API as Lecto API
    participant Cache as Redis (Token Store)

    App->>API: POST /auth/refresh { refresh_token }
    API->>Cache: Validate refresh_token (exists, not revoked, not expired)
    alt Token Valid
        Cache-->>API: Valid
        API->>API: Generate new access_token + rotate refresh_token
        API->>Cache: Store new refresh_token, invalidate old
        API-->>App: 200 { access_token, refresh_token, expires_in: 900 }
    else Token Invalid / Expired
        Cache-->>API: Invalid
        API-->>App: 401 { error: "session_expired" }
        Note over App: Force re-authentication
    end
```

> [!WARNING]
> Refresh tokens are **single-use**. Upon refresh, the old token is immediately invalidated. If a refresh token is used twice (replay attack), **all sessions for that user are revoked**.

### 3.4 Session Management

| Policy | Setting | Rationale |
|---|---|---|
| **Max concurrent sessions** | 5 devices | Prevents credential sharing at scale |
| **Session timeout (idle)** | 30 days | Students may not open app daily |
| **Session timeout (absolute)** | 90 days | Force periodic re-authentication |
| **Session binding** | Device fingerprint + IP range | Detects session hijacking |
| **Force logout** | On password change / account compromise | Invalidates all refresh tokens |

### 3.5 Device Management

Users can view and manage their active sessions from the app:

| Feature | Description |
|---|---|
| **Active sessions list** | Shows device name, OS, last active time, IP (city-level) |
| **Remote session revocation** | User can terminate any session except the current one |
| **New device notification** | Push notification + email when a new device signs in |
| **Trusted devices** | User can mark devices as trusted (skip MFA for 30 days) |

**Device Fingerprinting** (non-invasive):
- Device model + OS version
- App version
- Timezone
- Screen resolution hash

> [!NOTE]
> We do **not** collect IMEI, MAC address, or advertising IDs. Device fingerprinting is used solely for security purposes and is documented in our privacy policy.

### 3.6 Account Deletion (GDPR / App Store Compliance)

```mermaid
flowchart LR
    A["User requests deletion\n(Settings > Account > Delete)"] --> B{"Confirm via\nre-authentication"}
    B -->|Confirmed| C["Initiate 30-day\ngrace period"]
    C --> D["Disable account\nimmediately"]
    D --> E["Send confirmation\nemail"]
    E --> F{"User cancels\nwithin 30 days?"}
    F -->|Yes| G["Reactivate account"]
    F -->|No| H["Hard delete:\n- User record\n- All audio files\n- All transcripts\n- All notes\n- Payment history anonymized\n- Audit logs retained 1 year"]
    H --> I["Send final\nconfirmation email"]
```

**Deletion completeness checklist**:
- [ ] User profile data purged from PostgreSQL
- [ ] Audio files purged from Cloud Storage
- [ ] Transcripts and notes purged from database
- [ ] Search indexes cleared
- [ ] CDN/edge caches invalidated
- [ ] Firebase Auth account deleted
- [ ] Stripe customer record anonymized (retain transaction IDs for tax compliance)
- [ ] Analytics data anonymized (retain aggregated, non-identifiable metrics)
- [ ] Backup rotation ensures deletion propagates within 90 days

---

## 4. Data Security

### 4.1 Data Classification

| Classification | Examples | Encryption at Rest | Encryption in Transit | Retention |
|---|---|---|---|---|
| 🔴 **Critical** | Audio recordings, raw transcripts | AES-256-GCM | TLS 1.3 | User-controlled (max 2 years) |
| 🟠 **Sensitive** | User profile, email, institution | AES-256-GCM | TLS 1.3 | Account lifetime + 30 days |
| 🟡 **Internal** | Study notes, tags, folders | AES-256-GCM | TLS 1.3 | Account lifetime + 30 days |
| 🟢 **Public** | App metadata, feature flags | — | TLS 1.3 | Indefinite |

### 4.2 Encryption at Rest

#### On-Device (Mobile App)

| Component | Encryption Method | Key Storage | Notes |
|---|---|---|---|
| **SQLite database** | SQLCipher (AES-256-CBC) | iOS Keychain / Android Keystore | Database encrypted with per-device key |
| **Audio files** | AES-256-GCM | iOS Keychain / Android Keystore | Encrypted before writing to disk |
| **Cached transcripts** | AES-256-GCM | iOS Keychain / Android Keystore | Cleared on logout |
| **User preferences** | Platform secure storage | iOS Keychain / Android Keystore | No plaintext SharedPreferences |

```
┌──────────────────────────────────────────────────┐
│                 Mobile Device                     │
│                                                   │
│   ┌─────────────────────┐   ┌──────────────────┐ │
│   │   SQLCipher DB       │   │  Encrypted Audio │ │
│   │   (AES-256-CBC)      │   │  (AES-256-GCM)   │ │
│   │                      │   │                   │ │
│   │  - Transcripts       │   │  - .lecto files   │ │
│   │  - Notes metadata    │   │  (not playable    │ │
│   │  - Sync state        │   │   outside app)    │ │
│   └────────┬─────────────┘   └────────┬──────────┘ │
│            │                          │             │
│            ▼                          ▼             │
│   ┌─────────────────────────────────────────────┐  │
│   │     iOS Keychain / Android Keystore          │  │
│   │     (Hardware-backed when available)          │  │
│   │                                               │  │
│   │     - DB encryption key                       │  │
│   │     - Audio encryption key                    │  │
│   │     - Refresh token                           │  │
│   │     - Biometric auth token                    │  │
│   └─────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────┘
```

#### Server-Side (Cloud)

| Component | Encryption | Key Management | Notes |
|---|---|---|---|
| **PostgreSQL** | AES-256 (Google Cloud SQL) | Google-managed CMEK | Column-level encryption for PII fields |
| **Cloud Storage (audio)** | AES-256-GCM | Customer-Managed Encryption Keys (CMEK) via Cloud KMS | Per-user key hierarchy |
| **Cloud Storage (transcripts)** | AES-256-GCM | CMEK via Cloud KMS | Same key hierarchy as audio |
| **Redis cache** | In-memory encryption (TLS) | Ephemeral keys | No persistent sensitive data in cache |
| **Backups** | AES-256-GCM | Separate backup KMS key | Backups encrypted independently |

**Key Hierarchy**:

```
Root Key (Cloud KMS, HSM-backed)
├── User Key Encryption Key (KEK) — per user
│   ├── Audio Data Encryption Key (DEK)
│   ├── Transcript Data Encryption Key (DEK)
│   └── Notes Data Encryption Key (DEK)
├── Database Column Encryption Key
└── Backup Encryption Key
```

### 4.3 Encryption in Transit

| Requirement | Implementation | Enforcement |
|---|---|---|
| **TLS version** | TLS 1.3 (minimum TLS 1.2) | Server config; TLS 1.0/1.1 rejected |
| **Cipher suites** | `TLS_AES_256_GCM_SHA384`, `TLS_CHACHA20_POLY1305_SHA256` | Weak ciphers disabled |
| **Certificate** | Let's Encrypt / Google-managed SSL | Auto-renewal; HSTS enabled |
| **HSTS** | `max-age=31536000; includeSubDomains; preload` | All responses include header |
| **Certificate Transparency** | Enabled | SCT validation in app |
| **Internal service mesh** | mTLS (mutual TLS) | All service-to-service comms |

### 4.4 Audio File Security

Audio recordings require special handling due to their sensitive nature:

| Stage | Protection | Details |
|---|---|---|
| **Recording** | Encrypted buffer | Audio is encrypted in memory before writing |
| **Local storage** | AES-256-GCM encrypted `.lecto` files | Not playable by external media players |
| **Upload** | TLS 1.3 + chunked upload with integrity hash | SHA-256 checksum per chunk |
| **Cloud storage** | CMEK encryption + bucket-level access control | No public URLs; signed URLs for playback (15 min TTL) |
| **Playback** | Streamed via signed URL → decrypted in-app | Audio never cached unencrypted on device |
| **Deletion** | Crypto-shredding (delete DEK) | Data becomes irrecoverable without key |

### 4.5 API Key & Secrets Management

> [!CAUTION]
> **API keys, service account credentials, and secrets MUST NEVER appear in client-side code, version control, or build artifacts.**

| Secret Type | Storage Location | Access Method |
|---|---|---|
| **Firebase config** | Build-time injection (CI/CD) | Platform-specific config files (not in repo) |
| **Google Cloud service account** | Google Secret Manager | Workload Identity Federation |
| **Gemini API key** | Google Secret Manager | Server-side only; never sent to client |
| **Speech-to-Text credentials** | Google Secret Manager | Server-side only |
| **Stripe API keys** | Google Secret Manager | Server-side only |
| **Database credentials** | Google Secret Manager | Cloud SQL IAM authentication preferred |
| **JWT signing keys** | Google Cloud KMS | RSA private key never leaves KMS |

**Enforcement**:
- `.gitignore` includes all secret/config patterns (`*.env`, `*.keystore`, `serviceAccountKey.json`)
- Pre-commit hooks scan for secrets (using `gitleaks` or `trufflehog`)
- CI pipeline fails if secrets are detected in source code
- Secret rotation schedule: every 90 days (automated where possible)

### 4.6 PII Handling Policy

| PII Field | Collected | Purpose | Storage | Pseudonymized |
|---|---|---|---|---|
| Email address | ✅ | Authentication, notifications | Encrypted column | ❌ (primary identifier) |
| Display name | ✅ | Personalization | Encrypted column | ✅ in analytics |
| Institution name | ✅ (optional) | Feature customization | Encrypted column | ✅ in analytics |
| IP address | ✅ | Security (rate limiting, fraud) | Hashed after 30 days | ✅ |
| Device info | ✅ | Session security | Hashed | ✅ |
| Payment info | ❌ | Handled by Stripe | Stripe PCI DSS environment | N/A |
| Audio content | ✅ | Core feature | Encrypted storage | N/A |
| Lecture metadata | ✅ | Organization | Encrypted database | ✅ in analytics |

> [!IMPORTANT]
> Audio recordings may contain incidental PII (names mentioned in lectures, personal anecdotes). This is documented in our privacy policy. Users are advised to review recordings and are provided tools to redact sections.

---

## 5. API Security

### 5.1 API Authentication

Every API request (except public health checks and auth endpoints) requires a valid JWT:

```
GET /api/v1/lectures
Authorization: Bearer eyJhbGciOiJSUzI1NiIs...
Content-Type: application/json
X-Request-ID: req_abc123
X-Client-Version: 1.2.0
```

**Authentication enforcement**:

| Endpoint Category | Auth Required | Additional Checks |
|---|---|---|
| `POST /auth/login` | ❌ | Rate limited (10/min per IP) |
| `POST /auth/refresh` | Refresh Token | Token rotation enforced |
| `GET /health` | ❌ | Public |
| `GET /api/v1/lectures` | ✅ Bearer JWT | User can only see own lectures |
| `POST /api/v1/lectures/upload` | ✅ Bearer JWT | File size + type validation |
| `GET /api/v1/admin/*` | ✅ Bearer JWT | `role: admin` claim required |
| `DELETE /api/v1/account` | ✅ Bearer JWT + Re-auth | Critical action; requires fresh auth |

### 5.2 Rate Limiting

Rate limits are enforced at the API Gateway level (per user and per IP):

| Endpoint | Authenticated Limit | Unauthenticated Limit | Window | Burst |
|---|---|---|---|---|
| **Auth endpoints** | — | 10 req/min per IP | 1 min | 15 |
| **General API** | 100 req/min per user | — | 1 min | 150 |
| **Audio upload** | 5 uploads/hour per user | — | 1 hour | 5 |
| **Transcription trigger** | 10 req/hour per user | — | 1 hour | 10 |
| **AI notes generation** | 20 req/hour per user | — | 1 hour | 25 |
| **Search** | 30 req/min per user | — | 1 min | 45 |
| **Admin API** | 200 req/min per admin | — | 1 min | 300 |

**Rate limit headers** (returned on every response):

```
X-RateLimit-Limit: 100
X-RateLimit-Remaining: 73
X-RateLimit-Reset: 1751847300
Retry-After: 42          (only on 429 responses)
```

**Rate limit exceeded response**:
```json
{
  "error": "rate_limit_exceeded",
  "message": "Too many requests. Please retry after 42 seconds.",
  "retry_after": 42
}
```

### 5.3 Input Validation & Sanitization

| Input Type | Validation Rules | Sanitization |
|---|---|---|
| **Email** | RFC 5322 format, max 254 chars | Lowercase, trim whitespace |
| **Display name** | 1–100 chars, Unicode allowed | Strip control characters |
| **Lecture title** | 1–200 chars | HTML entity encoding |
| **Tags** | Max 20 tags, each 1–50 chars | Alphanumeric + hyphens only |
| **Audio file** | Max 500 MB, formats: `.m4a`, `.wav`, `.mp3`, `.ogg`, `.flac` | MIME type verification (magic bytes) |
| **Search query** | Max 500 chars | SQL injection prevention (parameterized queries) |
| **Pagination** | `page` ≥ 1, `per_page` 1–100 | Integer casting |
| **UUIDs** | RFC 4122 v4 format | Regex validation |
| **Transcript edits** | Max 50,000 chars per field | XSS sanitization (DOMPurify equivalent) |

**Server-side validation middleware** (applied globally):
- All JSON payloads validated against JSON Schema
- All file uploads scanned for malware (ClamAV)
- All string inputs checked for null bytes, control characters
- SQL queries use parameterized statements exclusively (no string interpolation)
- GraphQL introspection disabled in production

### 5.4 CORS Policy

```
Access-Control-Allow-Origin: https://app.lecto.app, https://admin.lecto.app
Access-Control-Allow-Methods: GET, POST, PUT, PATCH, DELETE, OPTIONS
Access-Control-Allow-Headers: Authorization, Content-Type, X-Request-ID, X-Client-Version
Access-Control-Expose-Headers: X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset
Access-Control-Max-Age: 86400
Access-Control-Allow-Credentials: true
```

> [!WARNING]
> `Access-Control-Allow-Origin: *` is **never** used. Origins are explicitly whitelisted. The mobile app communicates directly via HTTPS without CORS (native HTTP client), but the admin dashboard and marketing site require CORS.

### 5.5 Request Size Limits

| Endpoint | Max Body Size | Rationale |
|---|---|---|
| **General JSON API** | 1 MB | Prevents oversized payloads |
| **Audio upload** | 500 MB | 3-hour lecture at high quality ≈ 400 MB |
| **Profile image upload** | 5 MB | Compressed avatar |
| **Transcript edit** | 2 MB | Long lectures may have large transcripts |
| **Bulk export** | N/A (streamed response) | Server streams; no client upload |

Audio uploads use **chunked, resumable uploads**:
- Chunk size: 5 MB
- Each chunk includes SHA-256 checksum
- Upload can resume from last successful chunk
- Upload session expires after 24 hours
- Server validates final assembled file integrity

### 5.6 DDoS Protection

| Layer | Protection | Provider |
|---|---|---|
| **L3/L4 (Network)** | Google Cloud Armor | Automatic volumetric attack mitigation |
| **L7 (Application)** | Cloud Armor WAF rules + rate limiting | Custom rules for Lecto API patterns |
| **DNS** | Cloud DNS with DNSSEC | Prevents DNS amplification |
| **CDN** | Cloud CDN for static assets | Absorbs traffic spikes |
| **Bot detection** | reCAPTCHA Enterprise (on auth flows) | Invisible challenge on login/signup |
| **Geo-blocking** | Optional per-institution deployment | Configurable for enterprise clients |

### 5.7 API Versioning Strategy

```
Base URL: https://api.lecto.app/v1/
```

| Policy | Detail |
|---|---|
| **Versioning method** | URL path prefix (`/v1/`, `/v2/`) |
| **Deprecation notice** | Minimum 6 months before version sunset |
| **Sunset header** | `Sunset: Sat, 01 Jan 2028 00:00:00 GMT` on deprecated versions |
| **Max supported versions** | 2 concurrently (current + previous) |
| **Breaking change policy** | New version for breaking changes; non-breaking changes added to current version |

### 5.8 Security Headers

All API responses include:

```
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
X-XSS-Protection: 0
Content-Security-Policy: default-src 'none'; frame-ancestors 'none'
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: microphone=(), camera=(), geolocation=()
Cache-Control: no-store, no-cache, must-revalidate
Pragma: no-cache
```

> [!NOTE]
> `X-XSS-Protection: 0` is intentional — the legacy XSS filter is disabled in favor of CSP, as modern browsers' built-in XSS filters can introduce vulnerabilities.

---

## 6. Privacy & Compliance

### 6.1 GDPR Compliance Matrix

| GDPR Article | Requirement | Lecto Implementation | Status |
|---|---|---|---|
| **Art. 5** | Data minimization | Collect only data necessary for functionality | ✅ |
| **Art. 6** | Lawful basis | Consent (recording) + Contract (service) + Legitimate interest (security) | ✅ |
| **Art. 7** | Conditions for consent | Explicit consent before first recording; revocable | ✅ |
| **Art. 12–14** | Transparency | Privacy policy in plain language; data collection disclosures | ✅ |
| **Art. 15** | Right of access | User can view all data in-app + export | ✅ |
| **Art. 16** | Right to rectification | User can edit profile, transcripts, notes | ✅ |
| **Art. 17** | Right to erasure | Full account deletion with 30-day grace period | ✅ |
| **Art. 18** | Right to restriction | User can pause processing of their data | 🔜 |
| **Art. 20** | Data portability | Export in JSON + original audio format | ✅ |
| **Art. 25** | Privacy by design | Encryption by default, minimal data collection | ✅ |
| **Art. 28** | Processor agreements | DPAs signed with Google Cloud, Stripe | ✅ |
| **Art. 30** | Records of processing | Maintained in internal compliance system | ✅ |
| **Art. 32** | Security of processing | This document + implementation | ✅ |
| **Art. 33** | Breach notification | 72-hour notification to supervisory authority | ✅ (procedure defined) |
| **Art. 34** | Communication to data subjects | Email notification within 72 hours | ✅ (procedure defined) |
| **Art. 35** | DPIA | Data Protection Impact Assessment completed | ✅ |

### 6.2 Data Retention Policies

| Data Type | Active Retention | After Account Deletion | Legal Hold |
|---|---|---|---|
| **Audio recordings** | User-managed (default: indefinite while active) | Hard delete within 30 days | Preserved if required |
| **Transcripts** | Linked to audio lifecycle | Hard delete within 30 days | Preserved if required |
| **Study notes** | Linked to audio lifecycle | Hard delete within 30 days | Preserved if required |
| **User profile** | Account lifetime | Hard delete within 30 days | Anonymized |
| **Payment records** | Account lifetime | Anonymized (retain transaction IDs 7 years for tax) | Preserved |
| **Security audit logs** | 1 year rolling | Retained 1 year post-deletion | Preserved |
| **Analytics (aggregated)** | Indefinite | Already anonymized | N/A |
| **Support tickets** | 2 years | Anonymized within 90 days | Preserved if required |
| **Backups** | 30-day rolling | Data purged within 90 days (next backup rotation) | Preserved |

### 6.3 Right to Be Forgotten — Implementation

When a user exercises their right to erasure:

1. **Immediate** — Account is disabled; user cannot log in
2. **Within 24 hours** — Data removed from primary database and storage
3. **Within 7 days** — Data removed from search indexes and caches
4. **Within 30 days** — Grace period expires; deletion is irrevocable
5. **Within 90 days** — Data purged from all backup systems

**Exceptions** (data retained after erasure):
- Anonymized, aggregated analytics (no re-identification possible)
- Transaction records required by tax law (anonymized — amounts and dates only)
- Security audit logs (retained for 1 year; anonymized)

### 6.4 Data Export (Portability)

Users can request a full data export from **Settings → Privacy → Export My Data**:

| Included Data | Format | Delivery |
|---|---|---|
| Profile information | JSON | ZIP archive |
| All audio recordings | Original format (M4A/WAV/MP3) | ZIP archive |
| All transcripts | JSON + plain text | ZIP archive |
| All study notes | JSON + Markdown | ZIP archive |
| Tags and folder structure | JSON | ZIP archive |
| Usage history | JSON | ZIP archive |

- Export is prepared asynchronously (may take up to 24 hours for large accounts)
- User receives push notification + email when export is ready
- Download link is valid for 7 days and is a signed URL
- Export is encrypted with user's password-derived key
- Limited to 1 export request per 7 days (prevent abuse)

### 6.5 Recording Consent & Legal Considerations

> [!CAUTION]
> Recording lectures without consent may violate local laws, institutional policies, and professors' intellectual property rights. Lecto must implement safeguards.

#### Consent Framework

| Requirement | Implementation |
|---|---|
| **User education** | First-run tutorial explaining legal obligations |
| **Consent acknowledgment** | User must confirm they have permission before each recording session (configurable: per-session or per-course) |
| **Consent record** | App stores a timestamped consent acknowledgment |
| **Institutional policies** | In-app link to university recording policies |
| **Terms of Service** | Clearly states user is responsible for obtaining consent |
| **Professor notification** | Feature to generate a "I'm recording for personal study" card (digital or printable) |

#### Legal Landscape (Reference)

| Jurisdiction | Consent Requirement | Notes |
|---|---|---|
| **USA (Federal)** | One-party consent | User is the recording party |
| **USA (CA, FL, IL, etc.)** | Two-party / all-party consent | Professor must consent |
| **EU / UK** | Varies; GDPR applies to personal data | Legitimate interest may apply for personal study |
| **Australia** | Varies by state | Generally one-party consent |
| **Canada** | One-party consent (Criminal Code) | Privacy laws may additionally apply |

> [!IMPORTANT]
> Lecto is **not a legal advice provider**. The app clearly states that users must comply with local laws and institutional policies. The consent acknowledgment in the app is a risk-mitigation measure, not a legal guarantee.

### 6.6 Privacy Policy Requirements

The Lecto privacy policy must cover:

- [ ] What data is collected and why
- [ ] How audio recordings are processed (including third-party AI services)
- [ ] Data retention periods
- [ ] User rights (access, rectification, erasure, portability)
- [ ] Third-party data sharing (Google Cloud Speech-to-Text, Gemini)
- [ ] Cookie / tracking policy (for web dashboard)
- [ ] Contact information for Data Protection Officer (DPO)
- [ ] How to file a complaint with supervisory authority
- [ ] Children's privacy (COPPA — Lecto is for 13+ / 16+ depending on jurisdiction)
- [ ] International data transfers (Standard Contractual Clauses)
- [ ] Updates to the privacy policy (notification procedure)

---

## 7. Access Control Matrix (RBAC)

### 7.1 Role Definitions

```mermaid
graph TD
    A["🆓 Free User"] --> B["⭐ Premium User"]
    B --> C["🛡️ Admin"]
    C --> D["👑 Super Admin"]
```

| Role | Description | Assignment |
|---|---|---|
| **Free User** | Basic access; limited recordings/month | Default on signup |
| **Premium User** | Full access; unlimited recordings; advanced AI features | After payment / subscription |
| **Admin** | Content moderation; user management; analytics dashboard | Manual assignment by Super Admin |
| **Super Admin** | Full system access; infrastructure; billing management | Manual assignment; requires 2FA |

### 7.2 Permission Matrix

| Permission | Free User | Premium User | Admin | Super Admin |
|---|---|---|---|---|
| **Record lectures** | ✅ (5/month) | ✅ (unlimited) | ✅ | ✅ |
| **View own recordings** | ✅ | ✅ | ✅ | ✅ |
| **Generate transcript** | ✅ (5/month) | ✅ (unlimited) | ✅ | ✅ |
| **Generate AI study notes** | ❌ | ✅ | ✅ | ✅ |
| **Export data** | ✅ (JSON only) | ✅ (all formats) | ✅ | ✅ |
| **Custom AI prompts** | ❌ | ✅ | ✅ | ✅ |
| **Max recording length** | 30 min | 4 hours | 4 hours | Unlimited |
| **Max storage** | 1 GB | 50 GB | 50 GB | Unlimited |
| **Audio quality options** | Standard | Standard + High | Standard + High | All |
| **Delete own data** | ✅ | ✅ | ✅ | ✅ |
| **View other users' data** | ❌ | ❌ | ✅ (read-only) | ✅ |
| **Modify other users' data** | ❌ | ❌ | ❌ | ✅ |
| **Suspend/ban users** | ❌ | ❌ | ✅ | ✅ |
| **View analytics dashboard** | ❌ | ❌ | ✅ | ✅ |
| **Manage billing/plans** | ❌ | ❌ | ❌ | ✅ |
| **Manage admin accounts** | ❌ | ❌ | ❌ | ✅ |
| **Access infrastructure** | ❌ | ❌ | ❌ | ✅ |
| **View audit logs** | ❌ | ❌ | ✅ (limited) | ✅ |
| **Modify security config** | ❌ | ❌ | ❌ | ✅ |

### 7.3 Resource-Level Access Control

Every API endpoint enforces **resource-level isolation**:

```python
# Pseudocode — every data query includes user_id filter
def get_lectures(user_id: str) -> List[Lecture]:
    """User can ONLY access their own lectures."""
    return db.query(
        "SELECT * FROM lectures WHERE user_id = :uid AND deleted_at IS NULL",
        uid=user_id  # Extracted from JWT — never from request params
    )
```

| Principle | Implementation |
|---|---|
| **Tenant isolation** | All queries scoped by `user_id` from JWT (never client-supplied) |
| **No IDOR** | Resource IDs are UUIDs; access verified server-side on every request |
| **No horizontal escalation** | User A cannot access User B's data, even with valid resource ID |
| **No vertical escalation** | Free users cannot access premium endpoints; role checked on every request |
| **Admin access audit** | All admin access to user data is logged with justification field |

### 7.4 Permission Enforcement Architecture

```mermaid
flowchart TD
    A["Incoming Request"] --> B["API Gateway"]
    B --> C{"JWT Valid?"}
    C -->|No| D["401 Unauthorized"]
    C -->|Yes| E["Extract user_id + role"]
    E --> F{"Route requires\nhigher role?"}
    F -->|Yes, insufficient| G["403 Forbidden"]
    F -->|No / Sufficient| H{"Resource belongs\nto user?"}
    H -->|No and not Admin| I["404 Not Found"]
    H -->|Yes or Admin| J["Process Request"]
    J --> K["Audit Log Entry"]
```

> [!NOTE]
> When a user requests a resource they don't own, the API returns `404 Not Found` (not `403 Forbidden`) to prevent resource enumeration attacks.

---

## 8. Mobile App Security

### 8.1 Secure Storage

| Platform | Mechanism | Protection | Used For |
|---|---|---|---|
| **iOS** | Keychain Services (`kSecAttrAccessibleWhenUnlockedThisDeviceOnly`) | Hardware-backed Secure Enclave | Tokens, encryption keys, biometric auth |
| **Android** | Android Keystore (Hardware-backed TEE/StrongBox) | Keys never leave secure hardware | Tokens, encryption keys, biometric auth |
| **Flutter** | `flutter_secure_storage` package | Wraps platform Keychain/Keystore | Unified API for both platforms |

**What is stored securely**:
- ✅ JWT refresh tokens
- ✅ Database encryption key
- ✅ Audio file encryption key
- ✅ Biometric authentication state
- ✅ User session metadata

**What is NOT stored on device**:
- ❌ API keys (server-side only)
- ❌ Service account credentials
- ❌ Other users' data
- ❌ Plaintext passwords (Firebase Auth handles this)

### 8.2 Certificate Pinning

```dart
// Flutter implementation concept
class CertificatePinner {
  static const Map<String, List<String>> pins = {
    'api.lecto.app': [
      'sha256/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=', // Primary
      'sha256/BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=', // Backup
    ],
  };
}
```

| Policy | Detail |
|---|---|
| **Pinning method** | Public key pinning (HPKP-like, app-level) |
| **Pinned to** | Leaf certificate's public key SHA-256 hash |
| **Backup pins** | 2 backup pins (for certificate rotation) |
| **Pin rotation** | New pins deployed via app update before certificate rotation |
| **Failure mode** | Connection refused; user shown "Security error" message |
| **Reporting** | Failed pin validations reported to security monitoring endpoint |
| **Bypass for debugging** | Only in DEBUG builds; never in release builds |

### 8.3 Jailbreak / Root Detection

| Check | iOS | Android | Action on Detection |
|---|---|---|---|
| **OS modification** | Cydia/Sileo check, sandbox integrity | `su` binary, Magisk detection, SELinux status | ⚠️ Warning |
| **App integrity** | Code signature verification | APK signature verification, SafetyNet/Play Integrity API | ⚠️ Warning |
| **Hooking frameworks** | Frida, Substrate detection | Frida, Xposed detection | 🚫 Block sensitive operations |
| **Debugger attached** | `ptrace` anti-debug | `Debug.isDebuggerConnected()` | 🚫 Block in release builds |
| **Emulator** | Simulator detection | Emulator property checks | ⚠️ Warning (allow for development) |

**Policy on rooted/jailbroken devices**:

> [!WARNING]
> Lecto does **not** refuse to run on rooted/jailbroken devices entirely (this would alienate power users). Instead:
> - A **warning banner** is displayed explaining the security risk
> - **Biometric authentication** is disabled on compromised devices
> - **Offline storage** encryption keys are rotated more frequently
> - The security status is logged (but not used for account restriction)

### 8.4 Code Obfuscation

| Platform | Tool | Configuration |
|---|---|---|
| **Dart/Flutter** | `--obfuscate` + `--split-debug-info` | Enabled in release builds |
| **iOS (native)** | Xcode symbol stripping | `STRIP_SWIFT_SYMBOLS = YES` |
| **Android (native)** | R8/ProGuard | Custom rules for Flutter + plugins |
| **Source maps** | Stored securely; never shipped in APK/IPA | Used for crash reporting (Sentry/Crashlytics) |

### 8.5 Secure WebView Handling

| Rule | Implementation |
|---|---|
| **Minimal use** | WebViews used only for OAuth callbacks and terms/privacy pages |
| **JavaScript** | Disabled unless strictly required |
| **URL validation** | Only whitelisted domains loaded (`lecto.app`, `accounts.google.com`, `appleid.apple.com`) |
| **Cookie isolation** | WebView cookies are cleared after OAuth flow |
| **File access** | Disabled (`allowFileAccess = false`) |
| **Content loading** | HTTPS only; mixed content blocked |
| **Deep link handling** | Custom URL schemes validated against whitelist |

### 8.6 Biometric Authentication

```mermaid
sequenceDiagram
    participant U as User
    participant App as Lecto App
    participant Bio as Biometric API
    participant KS as Keychain/Keystore

    U->>App: Open app
    App->>App: Check biometric enrollment
    App->>Bio: Request biometric auth
    Bio->>U: Face ID / Fingerprint prompt
    U->>Bio: Authenticate
    Bio-->>App: Success + crypto proof
    App->>KS: Unlock stored refresh token
    KS-->>App: Refresh token
    App->>App: Resume session
```

| Setting | Default | User Configurable |
|---|---|---|
| **Biometric lock** | Disabled | ✅ Yes (Settings → Security) |
| **Lock after** | Immediately when app backgrounded | ✅ Options: Immediately / 1 min / 5 min |
| **Fallback** | Device PIN/password | ✅ (mandatory fallback) |
| **Max failed attempts** | 5 | ❌ (OS-enforced) |
| **Disabled on rooted devices** | Yes | ❌ |

---

## 9. Infrastructure Security

### 9.1 Network Architecture

```mermaid
graph TB
    subgraph "Internet"
        USER["Mobile App Users"]
        ADMIN["Admin Dashboard"]
    end

    subgraph "Edge Layer"
        CDN["Cloud CDN"]
        LB["Cloud Load Balancer\n(HTTPS Termination)"]
        ARMOR["Cloud Armor WAF"]
    end

    subgraph "VPC: lecto-prod (10.0.0.0/16)"
        subgraph "Public Subnet (10.0.1.0/24)"
            GW["API Gateway\n(Cloud Run)"]
        end

        subgraph "Private Subnet (10.0.2.0/24)"
            API["Core API Service\n(Cloud Run)"]
            WORKER1["Transcription Worker\n(Cloud Run Jobs)"]
            WORKER2["Notes Worker\n(Cloud Run Jobs)"]
        end

        subgraph "Data Subnet (10.0.3.0/24)"
            DB["Cloud SQL\n(PostgreSQL 15)"]
            REDIS["Memorystore\n(Redis 7)"]
            GCS["Cloud Storage\n(Audio + Transcripts)"]
        end
    end

    USER --> CDN
    ADMIN --> CDN
    CDN --> ARMOR
    ARMOR --> LB
    LB --> GW
    GW --> API
    API --> WORKER1
    API --> WORKER2
    API --> DB
    API --> REDIS
    API --> GCS
    WORKER1 --> GCS
    WORKER2 --> GCS
```

### 9.2 Network Security Controls

| Control | Implementation | Scope |
|---|---|---|
| **VPC** | Dedicated VPC with private subnets | All production services |
| **Private networking** | Services communicate via private IPs only | DB, Redis, Storage |
| **VPC Service Controls** | Restricts data exfiltration from GCP services | Cloud Storage, BigQuery |
| **Firewall rules** | Default deny; explicit allow per service | Ingress and egress |
| **Cloud NAT** | Outbound traffic via NAT (no public IPs on services) | All private services |
| **Private Google Access** | GCP services accessed via private endpoints | Cloud Storage, KMS, etc. |
| **DDoS protection** | Cloud Armor at edge | All inbound traffic |

### 9.3 Container Security

| Practice | Tool / Method | Frequency |
|---|---|---|
| **Base images** | Distroless / Alpine (minimal attack surface) | Every build |
| **Image scanning** | Google Artifact Registry vulnerability scanning | On push + daily |
| **No root** | Containers run as non-root user (`USER 1001`) | Every build |
| **Read-only filesystem** | `readOnlyRootFilesystem: true` | Runtime |
| **Resource limits** | CPU/memory limits set per service | Deployment config |
| **Image signing** | Binary Authorization (cosign) | On push |
| **No SSH** | No SSH daemon in containers; use Cloud Run exec for debugging | Always |

### 9.4 CI/CD Security

```mermaid
flowchart LR
    A["Developer Push"] --> B["GitHub Actions"]
    B --> C["Secret Scanning\n(gitleaks)"]
    C --> D["Dependency Audit\n(npm/pub audit)"]
    D --> E["SAST\n(Semgrep/CodeQL)"]
    E --> F["Unit + Integration Tests"]
    F --> G["Container Build"]
    G --> H["Image Vulnerability Scan\n(Trivy)"]
    H --> I{"Critical CVEs?"}
    I -->|Yes| J["🚫 Block Deploy"]
    I -->|No| K["Sign Image\n(cosign)"]
    K --> L["Deploy to Staging"]
    L --> M["Smoke Tests + DAST"]
    M --> N{"Tests Pass?"}
    N -->|No| O["🚫 Block Deploy"]
    N -->|Yes| P["Deploy to Production\n(Canary → Full)"]
```

| CI/CD Security Control | Implementation |
|---|---|
| **Branch protection** | `main` requires 2 approvals, status checks, signed commits |
| **Secret scanning** | `gitleaks` pre-commit hook + CI check |
| **SAST** | Semgrep with custom Lecto rulesets |
| **Dependency scanning** | `pub audit` (Dart), `npm audit` (Node.js), Dependabot alerts |
| **Container scanning** | Trivy (block on CRITICAL/HIGH) |
| **Infrastructure as Code** | Terraform with `tfsec` / `checkov` scanning |
| **Deployment** | Canary deployments with automatic rollback on error spike |
| **Secrets in CI** | GitHub Encrypted Secrets + OIDC to GCP (no long-lived keys) |

### 9.5 Dependency Management

| Practice | Frequency | Tool |
|---|---|---|
| **Automated dependency updates** | Weekly | Dependabot / Renovate |
| **Vulnerability alerts** | Real-time | GitHub Advisory Database |
| **License compliance** | On PR | FOSSA / license_finder |
| **Lockfile integrity** | On build | `pub.lock` / `package-lock.json` verification |
| **Supply chain attestation** | On build | SLSA Level 2 compliance target |

### 9.6 Security Headers (Admin Dashboard / Web)

The admin dashboard (web) includes additional headers:

```
Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https://storage.googleapis.com; connect-src 'self' https://api.lecto.app; frame-ancestors 'none'; base-uri 'self'; form-action 'self';
X-Content-Type-Options: nosniff
X-Frame-Options: DENY
Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
Referrer-Policy: strict-origin-when-cross-origin
Permissions-Policy: camera=(), microphone=(), geolocation=(), payment=()
Cross-Origin-Opener-Policy: same-origin
Cross-Origin-Embedder-Policy: require-corp
Cross-Origin-Resource-Policy: same-origin
```

---

## 10. Incident Response

### 10.1 Security Incident Classification

| Severity | Classification | Examples | Response Time | Resolution Target |
|---|---|---|---|---|
| 🔴 **P0 — Critical** | Active breach, data exfiltration | DB breach, auth bypass, ransomware | **15 minutes** | 4 hours |
| 🟠 **P1 — High** | Vulnerability actively exploited | XSS in production, IDOR discovered | **1 hour** | 24 hours |
| 🟡 **P2 — Medium** | Vulnerability discovered, not exploited | Dependency CVE (HIGH), misconfiguration | **4 hours** | 1 week |
| 🟢 **P3 — Low** | Minor security improvement | Dependency CVE (MEDIUM), header missing | **1 business day** | 1 month |
| 🔵 **P4 — Informational** | Security enhancement suggestion | Best practice improvement | **1 week** | Next sprint |

### 10.2 Incident Response Procedures

```mermaid
flowchart TD
    A["🚨 Incident Detected"] --> B["Triage & Classify\n(On-call engineer, 15 min)"]
    B --> C{"Severity?"}

    C -->|P0 Critical| D["Activate War Room\n- Page Security Lead\n- Page CTO\n- Page Legal"]
    C -->|P1 High| E["Alert Security Lead\n+ On-call team"]
    C -->|P2–P4| F["Create ticket\nAssign to security backlog"]

    D --> G["Containment\n- Isolate affected systems\n- Revoke compromised credentials\n- Enable enhanced logging"]
    E --> G

    G --> H["Investigation\n- Determine scope\n- Identify root cause\n- Assess data impact"]

    H --> I{"User data\ncompromised?"}
    I -->|Yes| J["Notify users (72h GDPR)\nNotify authorities\nNotify Apple/Google"]
    I -->|No| K["Internal resolution"]

    J --> L["Remediation\n- Patch vulnerability\n- Rotate secrets\n- Deploy fix"]
    K --> L

    L --> M["Recovery\n- Restore services\n- Verify fix\n- Monitor closely"]

    M --> N["Post-Incident Review\n- Blameless post-mortem\n- Update runbooks\n- Improve detection"]
```

### 10.3 Communication Plan

| Audience | Channel | Timing | Content |
|---|---|---|---|
| **Engineering team** | Slack #security-incidents | Immediately | Technical details, containment steps |
| **Leadership** | Slack + email | Within 1 hour (P0/P1) | Impact assessment, ETA |
| **Affected users** | Email + in-app notification | Within 72 hours (GDPR requirement) | What happened, what we did, what to do |
| **All users** | Status page (status.lecto.app) | During active incident | Service status updates |
| **Supervisory authority** | Formal written notification | Within 72 hours (GDPR Art. 33) | Data breach details per GDPR template |
| **Press / public** | Blog post | After resolution | Transparent disclosure |
| **Apple / Google** | Developer portal | As required | App removal risk mitigation |

### 10.4 Post-Incident Review

Every P0/P1 incident triggers a **blameless post-mortem** within 5 business days:

| Section | Content |
|---|---|
| **Summary** | What happened in 2–3 sentences |
| **Timeline** | Minute-by-minute chronology |
| **Impact** | Users affected, data exposed, duration |
| **Root cause** | Technical root cause analysis (5 Whys) |
| **Detection** | How was the incident detected? Could it have been faster? |
| **Response** | What went well? What could improve? |
| **Remediation** | What fixes were deployed? |
| **Action items** | Concrete tasks with owners and deadlines |
| **Systemic improvements** | Process/tooling changes to prevent recurrence |

---

## 11. Audit & Monitoring

### 11.1 Security Audit Logging

Every security-relevant event is logged to an immutable, append-only audit trail:

| Event Category | Events Logged | Retention |
|---|---|---|
| **Authentication** | Login (success/fail), logout, token refresh, password change, MFA enable/disable | 1 year |
| **Authorization** | Access denied (403), resource not found for user (404), role change | 1 year |
| **Data access** | Audio playback, transcript view, note view, data export | 1 year |
| **Data mutation** | Create/update/delete of recordings, transcripts, notes | 1 year |
| **Account lifecycle** | Signup, email change, account deletion request, deletion completed | 2 years |
| **Admin actions** | User suspension, data access, config change | 2 years |
| **Security events** | Rate limit exceeded, certificate pin failure, jailbreak detection | 1 year |
| **Infrastructure** | Deploy, secret rotation, firewall rule change | 2 years |

**Audit log entry structure**:

```json
{
  "timestamp": "2026-07-07T01:00:00.000Z",
  "event_type": "AUTH_LOGIN_SUCCESS",
  "actor": {
    "user_id": "usr_a1b2c3d4e5",
    "ip_address": "203.0.113.42",
    "user_agent": "Lecto/1.2.0 (iOS 19.0; iPhone14,3)",
    "device_id": "dev_x9y8z7"
  },
  "resource": {
    "type": "session",
    "id": "sess_m4n5o6"
  },
  "context": {
    "auth_method": "google_oauth",
    "mfa_used": false,
    "new_device": false
  },
  "result": "success",
  "request_id": "req_p7q8r9",
  "service": "auth-service",
  "environment": "production"
}
```

### 11.2 Anomaly Detection

| Anomaly | Detection Method | Alert Threshold | Response |
|---|---|---|---|
| **Brute force login** | Failed login count per IP/account | > 10 failures in 5 min | Temporary lockout (30 min) + alert |
| **Impossible travel** | Login from geographically distant locations | > 500 km apart within 1 hour | Force re-authentication + alert |
| **Mass data download** | Unusual volume of API calls to data endpoints | > 100 recordings accessed in 1 hour | Rate limit + admin alert |
| **Credential stuffing** | High volume of unique email login failures | > 50 unique emails failing from same IP | IP block + CAPTCHA + alert |
| **Privilege escalation attempt** | Requests to admin endpoints from non-admin | Any occurrence | Log + alert + block |
| **API abuse pattern** | Unusual endpoint usage pattern (scraping) | Statistical deviation from baseline | Rate limit + review |
| **Token replay** | Same refresh token used multiple times | Any occurrence | Revoke all user sessions + alert |
| **Off-hours admin access** | Admin API access outside business hours | Any occurrence (configurable) | Alert (allow with justification) |

### 11.3 Monitoring Stack

| Layer | Tool | Purpose |
|---|---|---|
| **Application metrics** | Cloud Monitoring (Prometheus-compatible) | Latency, error rates, throughput |
| **Structured logging** | Cloud Logging (structured JSON) | Centralized log aggregation |
| **Audit trail** | Cloud Logging (dedicated audit sink) | Immutable security event trail |
| **Error tracking** | Sentry | Application exceptions with context |
| **Uptime** | Cloud Monitoring Uptime Checks | Endpoint availability monitoring |
| **Alerting** | Cloud Monitoring + PagerDuty | On-call rotation and escalation |
| **Dashboards** | Grafana (Cloud Monitoring data source) | Real-time security posture visualization |
| **SIEM** | Cloud Security Command Center (SCC) | Threat detection, vulnerability management |

### 11.4 Regular Security Reviews

| Review Type | Frequency | Scope | Owner |
|---|---|---|---|
| **Automated dependency scan** | Daily | All dependencies | CI/CD pipeline |
| **Infrastructure security scan** | Weekly | Cloud configuration, IAM | SCC + manual review |
| **Code security review** | Every PR | Changed code | Peer review + Semgrep |
| **Access review** | Monthly | IAM roles, service accounts, admin access | Security lead |
| **Full security audit** | Quarterly | Entire stack | Security team |
| **Penetration test** | Annually (min) | External + internal | Third-party firm |
| **GDPR compliance review** | Annually | Data processing activities | DPO / Legal |
| **Incident response drill** | Semi-annually | IR procedures and communication | Security team |
| **Disaster recovery test** | Annually | Backup restoration, failover | Infrastructure team |

### 11.5 Penetration Testing

| Aspect | Detail |
|---|---|
| **Scope** | Mobile app (iOS + Android), API, admin dashboard, infrastructure |
| **Methodology** | OWASP Mobile Top 10, OWASP API Top 10, PTES |
| **Vendor** | Independent third-party security firm (rotated every 2 years) |
| **Frequency** | Full pentest annually; targeted testing after major features |
| **Bug bounty** | Planned — responsible disclosure program via security@lecto.app |
| **Findings handling** | P0/P1 findings: fix within 7 days; P2: 30 days; P3/P4: 90 days |
| **Report storage** | Encrypted, access restricted to Security Lead + CTO |

---

## 12. Third-Party Security

### 12.1 Third-Party Inventory

| Vendor | Service | Data Shared | DPA Signed | Compliance |
|---|---|---|---|---|
| **Google Cloud Platform** | Infrastructure, Cloud SQL, Storage, KMS | All Lecto data | ✅ | SOC 2, ISO 27001, GDPR |
| **Google Cloud Speech-to-Text** | Audio → text transcription | Audio recordings | ✅ (GCP DPA) | SOC 2, ISO 27001 |
| **Google Gemini API** | AI study notes generation | Transcript text | ✅ (GCP DPA) | SOC 2, ISO 27001 |
| **Firebase** | Authentication, push notifications | Email, device tokens | ✅ (GCP DPA) | SOC 2, ISO 27001 |
| **Stripe** | Payment processing | Email, payment method token | ✅ | PCI DSS Level 1, SOC 2 |
| **Sentry** | Error tracking | Stack traces (no PII) | ✅ | SOC 2, GDPR |
| **GitHub** | Source code hosting, CI/CD | Source code (no user data) | ✅ | SOC 2, ISO 27001 |

### 12.2 Google Cloud Speech-to-Text — Data Handling

| Concern | Policy |
|---|---|
| **Data retention** | Google does not retain audio data after processing (data logging disabled) |
| **Data usage for training** | Opted out of data usage for Google model improvement |
| **Processing location** | Configured for `us-central1` or `europe-west1` (user region-dependent) |
| **Encryption** | Audio encrypted in transit (TLS 1.3) and at rest within Google |
| **Access controls** | Only Lecto's service account can access our Speech-to-Text resources |
| **Configuration** | `data_logging: false` explicitly set in API requests |

```json
{
  "config": {
    "language_code": "en-US",
    "enable_automatic_punctuation": true,
    "enable_word_time_offsets": true,
    "model": "latest_long",
    "use_enhanced": true
  },
  "audio": {
    "uri": "gs://lecto-audio-prod/encrypted/usr_xxx/rec_yyy.flac"
  },
  "_comment": "data_logging is disabled at the project level"
}
```

### 12.3 Gemini API — Data Handling

| Concern | Policy |
|---|---|
| **Data retention** | Gemini API does not retain prompts/responses beyond request processing |
| **Data usage for training** | Opted out via Google Cloud API terms (paid tier, not free tier) |
| **PII in prompts** | Transcripts are pre-processed to redact known PII patterns before sending |
| **Prompt injection** | Input sanitized; system prompt instructs model to generate study notes only |
| **Output validation** | Generated notes validated for format compliance before delivery to user |
| **Rate limiting** | Per-user Gemini API quotas prevent abuse |
| **Fallback** | If Gemini is unavailable, notes generation is queued; user is notified |

**PII Redaction Pipeline** (before sending to Gemini):

```
Raw Transcript → Email Regex Redactor → Phone Regex Redactor
    → Named Entity Redactor (names, addresses) → Redacted Transcript → Gemini API
```

> [!TIP]
> PII redaction is best-effort. The privacy policy informs users that transcripts are processed by AI services, and users can review/edit transcripts before generating notes.

### 12.4 Firebase Security Rules

Lecto uses Firebase **only** for authentication (not Firestore/Realtime Database). However, if Firebase services are expanded, the following rules apply:

```javascript
// Firestore Security Rules (if used in future)
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Default: deny all
    match /{document=**} {
      allow read, write: if false;
    }

    // Users can only read/write their own document
    match /users/{userId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }

    // Lectures: user isolation
    match /users/{userId}/lectures/{lectureId} {
      allow read, write: if request.auth != null && request.auth.uid == userId;
    }
  }
}
```

```javascript
// Cloud Storage Security Rules (if used directly)
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // Default: deny all
    match /{allPaths=**} {
      allow read, write: if false;
    }

    // Users can only access their own audio files
    match /users/{userId}/{allPaths=**} {
      allow read, write: if request.auth != null
                         && request.auth.uid == userId
                         && resource.size < 500 * 1024 * 1024; // 500 MB max
    }
  }
}
```

### 12.5 Vendor Assessment Process

Before integrating any new third-party service:

| Step | Assessment | Required For |
|---|---|---|
| 1 | **Security questionnaire** (SIG Lite or equivalent) | All vendors |
| 2 | **SOC 2 Type II report review** | Vendors handling user data |
| 3 | **GDPR compliance verification** | All vendors (EU user data) |
| 4 | **Data Processing Agreement (DPA)** | Vendors processing personal data |
| 5 | **Penetration test results** (vendor's) | Vendors handling Critical/Sensitive data |
| 6 | **Insurance verification** (cyber liability) | Vendors handling Critical data |
| 7 | **Ongoing monitoring** (security advisories) | All vendors |
| 8 | **Annual re-assessment** | All vendors |

---

## 13. Security Checklist

### 13.1 Pre-Launch Security Checklist

| # | Category | Item | Status |
|---|---|---|---|
| 1 | Auth | Firebase Auth configured with email enumeration protection | ⬜ |
| 2 | Auth | OAuth 2.0 flows tested (Google, Apple) | ⬜ |
| 3 | Auth | JWT RS256 signing with key rotation | ⬜ |
| 4 | Auth | Refresh token rotation and replay detection | ⬜ |
| 5 | Auth | Account deletion flow end-to-end tested | ⬜ |
| 6 | Data | SQLCipher encryption enabled on all local databases | ⬜ |
| 7 | Data | Audio files encrypted at rest on device | ⬜ |
| 8 | Data | Cloud Storage CMEK encryption configured | ⬜ |
| 9 | Data | Cloud SQL encryption at rest verified | ⬜ |
| 10 | Data | TLS 1.3 enforced on all endpoints | ⬜ |
| 11 | Data | No secrets in source code (gitleaks clean) | ⬜ |
| 12 | Data | PII fields encrypted at column level | ⬜ |
| 13 | API | Rate limiting configured and tested | ⬜ |
| 14 | API | Input validation on all endpoints | ⬜ |
| 15 | API | CORS whitelist configured (no wildcard) | ⬜ |
| 16 | API | Security headers on all responses | ⬜ |
| 17 | API | Request size limits enforced | ⬜ |
| 18 | API | Cloud Armor WAF rules active | ⬜ |
| 19 | Privacy | GDPR compliance matrix completed | ⬜ |
| 20 | Privacy | Privacy policy published and reviewed by legal | ⬜ |
| 21 | Privacy | Recording consent flow implemented | ⬜ |
| 22 | Privacy | Data export feature functional | ⬜ |
| 23 | Privacy | Data retention automation configured | ⬜ |
| 24 | RBAC | Role-based access control enforced server-side | ⬜ |
| 25 | RBAC | Resource-level isolation tested (no IDOR) | ⬜ |
| 26 | RBAC | Admin actions audit-logged | ⬜ |
| 27 | Mobile | Secure storage for tokens/keys (Keychain/Keystore) | ⬜ |
| 28 | Mobile | Certificate pinning configured | ⬜ |
| 29 | Mobile | Jailbreak/root detection active | ⬜ |
| 30 | Mobile | Code obfuscation in release builds | ⬜ |
| 31 | Mobile | WebView hardening applied | ⬜ |
| 32 | Infra | VPC with private subnets configured | ⬜ |
| 33 | Infra | Container images scanned for vulnerabilities | ⬜ |
| 34 | Infra | CI/CD pipeline includes security gates | ⬜ |
| 35 | Infra | Non-root container execution | ⬜ |
| 36 | Infra | Binary authorization enabled | ⬜ |
| 37 | Monitor | Audit logging pipeline active | ⬜ |
| 38 | Monitor | Anomaly detection rules configured | ⬜ |
| 39 | Monitor | Alerting and on-call rotation set up | ⬜ |
| 40 | Third-party | Speech-to-Text data logging disabled | ⬜ |
| 41 | Third-party | Gemini API opted out of training data use | ⬜ |
| 42 | Third-party | DPAs signed with all data processors | ⬜ |
| 43 | IR | Incident response plan documented and drilled | ⬜ |
| 44 | IR | Security contact (security@lecto.app) configured | ⬜ |
| 45 | IR | Breach notification template prepared | ⬜ |

### 13.2 Ongoing Security Maintenance

| Cadence | Activity | Owner |
|---|---|---|
| **Daily** | Review automated security scan results | On-call engineer |
| **Weekly** | Review dependency update PRs | Engineering lead |
| **Monthly** | IAM access review | Security lead |
| **Quarterly** | Full security audit + document review | Security team |
| **Semi-annually** | Incident response tabletop exercise | Security team + leadership |
| **Annually** | External penetration test | Third-party firm |
| **Annually** | GDPR compliance review | DPO / Legal |
| **On every release** | SAST + dependency scan + container scan | CI/CD pipeline |
| **On major feature** | Threat model update | Security team + feature lead |

---

## 14. Document History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0.0 | 2026-07-07 | Lecto Security Team | Initial document creation |

---

> [!NOTE]
> This is a living document. All changes must be reviewed by the Security Lead and approved via PR before merging. Questions or concerns should be directed to **security@lecto.app**.

---

*© 2026 Lecto. Internal & Confidential.*
