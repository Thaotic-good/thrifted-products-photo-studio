# EXECUTION_PLAN.md
## AI Product Photography Augmentation for Resellers

> **Note for AI Assistants:** This document and its related files (BE_EXECUTION.md, FE_EXECUTION.md) are designed to be modified by AI agents. Feel free to update, expand, or refactor any section based on new requirements, improvements, or technical decisions. Maintain the structured format and cross-references between documents.

---

## Document Structure

This is the **master execution plan** that provides a high-level overview of the entire project. For detailed implementation instructions, refer to:

- **[BE_EXECUTION.md](./BE_EXECUTION.md)** - Backend/API implementation details (Next.js API routes, Supabase, Replicate integration, webhooks)
- **[FE_EXECUTION.md](./FE_EXECUTION.md)** - Frontend implementation details (React components, UI/UX, real-time updates, state management)

---

## Project Overview

**Goal:** Build a web application that enables online resellers to upload raw product photos and enhance them using AI. The system supports batch processing across two distinct pipelines: "Objects" (background replacement) and "Clothing" (virtual try-on).

**Tech Stack:**
- Frontend/Backend: Next.js 16
- Database: Supabase (PostgreSQL)
- Image Processing: Replicate API
- Deployment: Vercel
- Storage: Supabase Storage

**Key Constraint:** Minimize moving parts for junior developer maintainability on free tier limits.

---

## Table of Contents

1. [System Architecture](#system-architecture)
2. [Pipeline Modes](#pipeline-modes)
3. [Project Structure](#project-structure)
4. [Implementation Roadmap](#implementation-roadmap)
5. [Tech Stack Deep Dive](#tech-stack-deep-dive)
6. [Data Flow](#data-flow)
7. [Development Workflow](#development-workflow)
8. [Testing Strategy](#testing-strategy)
9. [Deployment & Monitoring](#deployment--monitoring)
10. [Cost & Performance](#cost--performance)

---

## System Architecture

### High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         CLIENT (Browser)                        │
│  - Upload Interface (FE_EXECUTION.md: Upload Component)        │
│  - Real-time Monitoring (FE_EXECUTION.md: BatchMonitor)        │
│  - Authentication UI (FE_EXECUTION.md: Auth Flow)              │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           │ HTTPS
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│                    NEXT.JS 16 (Vercel)                          │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  API Routes (BE_EXECUTION.md: API Endpoints)             │  │
│  │  - /api/upload          - /api/process-batch             │  │
│  │  - /api/batches/[id]    - /api/webhook/replicate        │  │
│  │  - /api/results/[id]    - /api/health                    │  │
│  └──────────────────────────────────────────────────────────┘  │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │  Middleware (BE_EXECUTION.md: Auth Middleware)           │  │
│  │  - JWT Validation        - RLS Enforcement               │  │
│  └──────────────────────────────────────────────────────────┘  │
└────────────┬────────────────────────────┬─────────────────────┘
             │                            │
             │                            │
             ▼                            ▼
┌────────────────────────┐    ┌──────────────────────────────┐
│   SUPABASE             │    │   REPLICATE API              │
│                        │    │                              │
│  ┌──────────────────┐  │    │  ┌────────────────────────────────┐ │
│  │  PostgreSQL DB   │  │    │  │  AI Models (see replicate.ts): │ │
│  │  (Schema)        │  │    │  │  - BACKGROUND_REMOVAL_MODEL    │ │
│  └──────────────────┘  │    │  │  - BACKGROUND_GENERATION_MODEL │ │
│                        │    │  │  - LIGHTING_UNIFICATION_MODEL  │ │
│  ┌──────────────────┐  │    │  │  - VIRTUAL_TRYON_MODEL         │ │
│  │  Storage         │  │    │  └────────────────────────────────┘ │
│  │  - uploads/      │  │    │                              │
│  │  - results/      │  │    │  Webhook Callback:          │
│  │  - models/       │  │    │  POST /api/webhook/replicate│
│  └──────────────────┘  │    └──────────────────────────────┘
│                        │
│  ┌──────────────────┐  │
│  │  Realtime        │  │◄─── Subscribes to DB changes
│  │  (WebSocket)     │  │     (FE_EXECUTION.md: Real-time)
│  └──────────────────┘  │
│                        │
│  ┌──────────────────┐  │
│  │  Auth (JWT)      │  │
│  └──────────────────┘  │
└────────────────────────┘
```

### Component Responsibilities

| Layer | Components | Reference Document |
|-------|-----------|-------------------|
| **Frontend** | Upload UI, Batch Monitor, Auth Pages | [FE_EXECUTION.md](./FE_EXECUTION.md) |
| **Backend** | API Routes, Webhooks, Middleware | [BE_EXECUTION.md](./BE_EXECUTION.md) |
| **Database** | PostgreSQL Schema, RLS Policies | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 3 |
| **Storage** | Supabase Storage (images) | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 4 |
| **AI Processing** | Replicate API Integration | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 6 |

---

## Pipeline Modes

### Pipeline A: Objects (Background Replacement)

**Purpose:** Transform raw product photos into professional images with curated backgrounds.

**Steps:**
1. **Background Removal** → Transparent PNG (Model: `BACKGROUND_REMOVAL_MODEL` — see `app/lib/replicate.ts`)
2. **Professional Background** → Final image with studio-quality background (Model: `BACKGROUND_GENERATION_MODEL` — see `app/lib/replicate.ts`)
3. **Lighting Unification** → Harmonise lighting between composited foreground and new background (Model: `LIGHTING_UNIFICATION_MODEL` — see `app/lib/replicate.ts`)

**Use Cases:** Footwear, electronics, accessories, furniture

**Implementation Details:** See [BE_EXECUTION.md](./BE_EXECUTION.md) Section 6.1

---

### Pipeline B: Clothing (Virtual Try-On)

**Purpose:** Enable customers to see how garments look on selected human models.

**Steps:**
1. **Garment Detection** → Extract clean garment image
2. **Model Selection** → Choose from pre-loaded models or user uploads
3. **Virtual Try-On** → AI overlays garment onto model (Model: `VIRTUAL_TRYON_MODEL` — see `app/lib/replicate.ts`)

**Use Cases:** T-shirts, dresses, jackets, apparel

**Implementation Details:** See [BE_EXECUTION.md](./BE_EXECUTION.md) Section 6.2

---

## Project Structure

```
thrifted-products-photo-studio/
├── app/
│   ├── api/                        # Backend (BE_EXECUTION.md)
│   │   ├── upload/
│   │   │   └── route.ts            # File upload handler
│   │   ├── process-batch/
│   │   │   └── route.ts            # Replicate API trigger
│   │   ├── batches/
│   │   │   └── [id]/
│   │   │       └── route.ts        # Batch status endpoint
│   │   ├── webhook/
│   │   │   └── replicate/
│   │   │       └── route.ts        # Webhook callback handler
│   │   └── health/
│   │       └── route.ts            # Health check
│   │
│   ├── components/                 # Frontend (FE_EXECUTION.md)
│   │   ├── UploadForm.tsx          # File upload UI
│   │   ├── BatchMonitor.tsx        # Real-time progress monitor
│   │   ├── PipelineSelector.tsx    # Objects/Clothing selector
│   │   ├── JobCard.tsx             # Individual job display
│   │   └── ResultsGallery.tsx      # Processed images gallery
│   │
│   ├── lib/                        # Shared utilities
│   │   ├── supabase/
│   │   │   ├── client.ts           # Browser client
│   │   │   ├── server.ts           # Server client
│   │   │   └── proxy.ts            # Auth proxy
│   │   ├── replicate.ts            # Replicate API wrapper
│   │   └── logging.ts              # Logging utility
│   │
│   ├── auth/                        # Auth pages (FE_EXECUTION.md)
│   │   ├── login/
│   │   │   └── page.tsx
│   │   └── signup/
│   │       └── page.tsx
│   │
│   ├── dashboard/                   # Main app pages (FE_EXECUTION.md)
│   │   └── page.tsx                 # User dashboard
│   ├── upload/
│   │   └── page.tsx                 # Upload page
│   ├── batch/
│   │   └── [id]/
│   │       └── page.tsx             # Batch detail view
│   │
│   ├── layout.tsx                  # Root layout
│   └── page.tsx                    # Landing page
│
├── supabase/
│   ├── migrations/                 # Database migrations (BE_EXECUTION.md)
│   │   ├── 001_initial_schema.sql
│   │   ├── 002_rls_policies.sql
│   │   └── 003_storage_buckets.sql
│   └── seed.sql                    # Sample data (development)
│
├── public/
│   └── models/                     # Pre-loaded model images (clothing)
│
├── tests/
│   ├── api/                        # Backend tests
│   │   ├── upload.test.ts
│   │   └── webhook.test.ts
│   └── components/                 # Frontend tests
│       ├── UploadForm.test.tsx
│       └── BatchMonitor.test.tsx
│
├── .env.local                      # Environment variables
├── .env.example                    # Example env file
├── next.config.ts                  # Next.js configuration
├── package.json
├── tsconfig.json
├── EXECUTION_PLAN.md              # This file (master overview)
├── BE_EXECUTION.md                # Backend detailed plan
└── FE_EXECUTION.md                # Frontend detailed plan
```

---

## Implementation Roadmap

### Phase 1: Foundation (Week 1)

**Goals:**
- Project setup
- Database schema
- Authentication flow
- Basic file upload

**Tasks:**

| Task | Owner | Reference |
|------|-------|-----------|
| Initialize Next.js 16 project | Dev | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 1 |
| Setup Supabase project | Dev | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 2 |
| Create database schema | Backend | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 3 |
| Implement auth middleware | Backend | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 5 |
| Create login/signup pages | Frontend | [FE_EXECUTION.md](./FE_EXECUTION.md) Section 2 |
| Setup environment variables | Dev | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 1.3 |

**Deliverables:**
✅ Working authentication flow  
✅ Database tables created  
✅ Storage buckets configured  
✅ Local development environment ready  

---

### Phase 2: Core Backend (Week 2)

**Goals:**
- API endpoints
- Replicate integration
- Webhook handling
- Batch processing logic

**Tasks:**

| Task | Owner | Reference |
|------|-------|-----------|
| Build `/api/upload` endpoint | Backend | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 7 |
| Build `/api/process-batch` endpoint | Backend | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 8 |
| Implement webhook handler | Backend | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 9 |
| Setup Replicate API integration | Backend | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 6 |
| Implement error handling | Backend | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 11 |
| Add logging & monitoring | Backend | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 12 |

**Deliverables:**
✅ Upload endpoint working  
✅ Replicate API calls successful  
✅ Webhooks receiving callbacks  
✅ Database updates on completion  

---

### Phase 3: Frontend UI (Week 3)

**Goals:**
- Upload interface
- Real-time monitoring
- Results display
- User dashboard

**Tasks:**

| Task | Owner | Reference |
|------|-------|-----------|
| Build UploadForm component | Frontend | [FE_EXECUTION.md](./FE_EXECUTION.md) Section 3 |
| Build BatchMonitor component | Frontend | [FE_EXECUTION.md](./FE_EXECUTION.md) Section 4 |
| Implement Realtime subscriptions | Frontend | [FE_EXECUTION.md](./FE_EXECUTION.md) Section 5 |
| Create results gallery | Frontend | [FE_EXECUTION.md](./FE_EXECUTION.md) Section 6 |
| Build user dashboard | Frontend | [FE_EXECUTION.md](./FE_EXECUTION.md) Section 7 |
| Add responsive design | Frontend | [FE_EXECUTION.md](./FE_EXECUTION.md) Section 8 |

**Deliverables:**
✅ Functional upload UI  
✅ Real-time progress updates  
✅ Image preview & download  
✅ Mobile-responsive design  

---

### Phase 4: Testing & Deployment (Week 4)

**Goals:**
- End-to-end testing
- Performance optimization
- Production deployment
- Monitoring setup

**Tasks:**

| Task | Owner | Reference |
|------|-------|-----------|
| Write API integration tests | Backend | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 13 |
| Write component tests | Frontend | [FE_EXECUTION.md](./FE_EXECUTION.md) Section 9 |
| Optimize bundle size | Frontend | [FE_EXECUTION.md](./FE_EXECUTION.md) Section 10 |
| Setup error tracking (Sentry) | DevOps | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 12 |
| Deploy to Vercel | DevOps | Section 9 below |
| Configure production env vars | DevOps | [BE_EXECUTION.md](./BE_EXECUTION.md) Section 14 |

**Deliverables:**
✅ All tests passing  
✅ Deployed to production  
✅ Monitoring & alerts configured  
✅ Performance optimized  

---

## Tech Stack Deep Dive

### Frontend: Next.js 16 + React

**Why Next.js 16?**
- Server-side rendering (SSR) for auth pages
- API routes for backend (monorepo simplicity)
- Built-in optimization (images, fonts)
- Excellent Vercel integration

**Key Libraries:**
- `@supabase/ssr` - Supabase client for Next.js
- `react-dropzone` - File upload UI
- `date-fns` - Date formatting
- `clsx` or `tailwindcss` - Styling

**Details:** [FE_EXECUTION.md](./FE_EXECUTION.md) Section 1

---

### Backend: Next.js API Routes + Supabase

**Why API Routes?**
- No separate backend server needed
- Same codebase as frontend
- Easy deployment to Vercel
- Built-in middleware support

**Key Features:**
- File upload handling (multipart/form-data)
- Async webhook processing
- Database queries (Supabase client)
- Authentication middleware

**Details:** [BE_EXECUTION.md](./BE_EXECUTION.md) Section 1

---

### Database: Supabase (PostgreSQL)

**Schema Overview:**
- `image_processing_jobs` - Individual image processing records
- `image_batches` - Batch grouping & stats
- `processing_models` - AI model registry
- `user_model_uploads` - Custom models for clothing pipeline

**Key Features:**
- Row-level security (RLS)
- Real-time subscriptions (WebSocket)
- Built-in authentication
- Storage integration

**Details:** [BE_EXECUTION.md](./BE_EXECUTION.md) Section 3

---

### AI Processing: Replicate API

**Models Used:**

> All model identifiers are defined as named constants in `app/lib/replicate.ts`.
> The table below is a summary — update that file (not this table) when swapping models.
> **(Note: later iteration may include resolution enhancement model)**
> 
| Pipeline | Constant | Replicate Model              | Cost/Run | Avg Time |
|----------|----------|------------------------------|---|-----|
| Objects – BG Removal    | `BACKGROUND_REMOVAL_MODEL`    | `bria/remove-background`     | ~$0.018 | |
| Objects – BG Generation | `BACKGROUND_GENERATION_MODEL` | `bria/generate-background`   | ~$0.4 |  |
| Objects – Lighting      | `LIGHTING_UNIFICATION_MODEL`  | `zsxkib/ic-light-background` | ~$0.033 | ~34 s |
| Clothing – Try-On       | `VIRTUAL_TRYON_MODEL`         | `DCI-VTON` ⚠ self-hosted     |   |  |

**Integration:**
- Async predictions with webhooks
- Status polling fallback
- Error handling & retries

**Details:** [BE_EXECUTION.md](./BE_EXECUTION.md) Section 6

---

## Data Flow

### Upload to Completion Flow

```
1. USER ACTION (FE)
   └─→ Select pipeline (objects/clothing)
   └─→ Upload files (1-10 images)
   └─→ Submit form

2. FRONTEND (FE_EXECUTION.md: Section 3)
   └─→ Validate files (size, type)
   └─→ POST /api/upload with FormData
   └─→ Navigate to /app/batch/[id]

3. BACKEND /api/upload (BE_EXECUTION.md: Section 7)
   └─→ Authenticate user (JWT)
   └─→ Create batch record (status: processing)
   └─→ For each file:
       ├─→ Upload to Supabase Storage (uploads/{user_id}/raw/{batch_id}/)
       └─→ Create image_processing_jobs row (status: pending)
   └─→ Return batch_id

4. FRONTEND BatchMonitor (FE_EXECUTION.md: Section 4)
   └─→ Fetch batch data (GET /api/batches/[id])
   └─→ Subscribe to Realtime (postgres_changes)
   └─→ Display pending jobs

5. USER ACTION (FE)
   └─→ Click "Start Processing"
   └─→ POST /api/process-batch

6. BACKEND /api/process-batch (BE_EXECUTION.md: Section 8)
   └─→ Fetch pending jobs for batch
   └─→ For each job:
       ├─→ Determine Replicate model (based on pipeline)
       ├─→ Create prediction with webhook URL
       ├─→ Store webhook_id & replicate_run_id
       └─→ Update status: processing
   └─→ Return job summary

7. REPLICATE API (Async)
   └─→ Process images (2-30 seconds)
   └─→ On completion, POST to /api/webhook/replicate

8. BACKEND /api/webhook/replicate (BE_EXECUTION.md: Section 9)
   └─→ Validate webhook signature
   └─→ Find job by webhook_id
   └─→ Download result from Replicate
   └─→ Upload to Supabase Storage (results/{user_id}/processed/{batch_id}/)
   └─→ Update job: status=completed, result_image_url
   └─→ Update batch stats (completed_count++)

9. SUPABASE REALTIME
   └─→ Broadcast DB change to subscribed clients

10. FRONTEND BatchMonitor (FE_EXECUTION.md: Section 5)
    └─→ Receive Realtime update
    └─→ Display result image
    └─→ Show download button
    └─→ Update batch progress bar
```

---

## Development Workflow

### Local Setup

```bash
# 1. Clone repository
git clone <repo-url>
cd ai-photo-augmentation

# 2. Install dependencies
npm install

# 3. Setup environment variables
cp .env.example .env.local
# Edit .env.local with your credentials

# 4. Run database migrations (Supabase)
# Via Supabase dashboard or CLI

# 5. Start development server
npm run dev

# 6. Access app
# http://localhost:3000
```

### Environment Variables

See [BE_EXECUTION.md](./BE_EXECUTION.md) Section 1.3 for complete list.

---

### Git Workflow

```bash
# Feature branch workflow
git checkout -b feature/upload-component
# ... make changes ...
git commit -m "feat: add upload component"
git push origin feature/upload-component
# Create PR, review, merge to main
```

### Branch Strategy

- `main` - Production-ready code
- `develop` - Integration branch
- `feature/*` - Feature branches
- `fix/*` - Bug fixes
- `docs/*` - Documentation updates

---

## Testing Strategy

### Backend Tests

**Tools:** Jest, Supertest

**Coverage:**
- API endpoint responses
- Webhook signature validation
- Database operations
- Error handling

**Reference:** [BE_EXECUTION.md](./BE_EXECUTION.md) Section 13

---

### Frontend Tests

**Tools:** Jest, React Testing Library

**Coverage:**
- Component rendering
- User interactions
- Form validation
- Realtime updates

**Reference:** [FE_EXECUTION.md](./FE_EXECUTION.md) Section 9

---

### End-to-End Tests

**Tools:** Playwright or Cypress

**Scenarios:**
- Complete upload → processing → result flow
- Authentication flow
- Error scenarios (network failures)

---

## Deployment & Monitoring

### Deployment (Vercel)

```bash
# 1. Install Vercel CLI
npm i -g vercel

# 2. Link project
vercel link

# 3. Set environment variables
vercel env add NEXT_PUBLIC_SUPABASE_URL
vercel env add SUPABASE_SERVICE_ROLE_KEY
vercel env add REPLICATE_API_TOKEN
# ... etc

# 4. Deploy
vercel --prod
```

**Reference:** [BE_EXECUTION.md](./BE_EXECUTION.md) Section 14

---

### Monitoring

**Tools:**
- Vercel Analytics (performance)
- Supabase Dashboard (database/storage usage)
- Sentry (error tracking)
- Replicate Dashboard (API usage & costs)

**Health Check:** `GET /api/health`

**Reference:** [BE_EXECUTION.md](./BE_EXECUTION.md) Section 12

---

## Cost & Performance

### Free Tier Limits

| Service | Limit | Solution |
|---------|-------|----------|
| Vercel Functions | 10s timeout | Use webhooks (async) |
| Supabase Storage | 1GB | Delete old results (30 days) |
| Supabase Database | Unlimited rows | Archive old batches monthly |
| Replicate API | $20 free credits | Monitor usage, optimize |

### Performance Optimization

**Frontend:**
- Image compression before upload
- Lazy loading components
- Code splitting (dynamic imports)

**Backend:**
- Batch webhook processing
- Connection pooling (Supabase)
- Caching (if needed)

**Reference:**
- Frontend: [FE_EXECUTION.md](./FE_EXECUTION.md) Section 10
- Backend: [BE_EXECUTION.md](./BE_EXECUTION.md) Section 15

---

## Next Steps

### Immediate Actions

1. **Backend Team:** Follow [BE_EXECUTION.md](./BE_EXECUTION.md) to implement API endpoints
2. **Frontend Team:** Follow [FE_EXECUTION.md](./FE_EXECUTION.md) to build UI components
3. **DevOps:** Setup Vercel & Supabase projects
4. **All:** Daily standup to sync progress

### Future Enhancements

- **Batch editing:** Adjust background prompts after upload
- **Result variations:** Generate multiple background options
- **Model marketplace:** Allow users to upload & sell custom models
- **Advanced analytics:** Track popular pipelines, processing times
- **Social sharing:** Share results directly to social media

---

## Document Maintenance

**Last Updated:** February 12, 2026  
**Version:** 2.0  
**Maintainer:** Development Team  

**Change Log:**
- v2.0 (Feb 2026): Restructured as master plan with BE/FE references
- v1.0 (Feb 2026): Initial comprehensive execution plan

**Related Documents:**
- [BE_EXECUTION.md](./BE_EXECUTION.md) - Backend implementation guide
- [FE_EXECUTION.md](./FE_EXECUTION.md) - Frontend implementation guide

---

**Status:** Ready for Implementation  
**Team Size:** 1-2 developers (junior-friendly)  
**Timeline:** 4 weeks to MVP
