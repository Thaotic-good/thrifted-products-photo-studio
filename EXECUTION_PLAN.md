# EXECUTION_PLAN.md
## AI Product Photography Augmentation for Resellers

**Project Overview:** Build a web application that enables online resellers to upload raw product photos and enhance them using AI. The system supports batch processing across two distinct pipelines: "Objects" (background replacement) and "Clothing" (virtual try-on).

**Tech Stack:**
- Frontend/Backend: Next.js 16
- Database: Supabase
- Image Processing: Replicate API
- Deployment: Vercel
- Storage: Supabase Storage

**Key Constraint:** Minimize moving parts for junior developer maintainability on free tier limits.

---

## Table of Contents

1. [Project Architecture](#project-architecture)
2. [Pipeline Modes](#pipeline-modes)
3. [Database Schema](#database-schema)
4. [Batch Processing Architecture](#batch-processing-architecture)
5. [API Endpoints](#api-endpoints)
6. [Implementation Workflow](#implementation-workflow)
7. [Frontend Components](#frontend-components)
8. [Error Handling & Monitoring](#error-handling--monitoring)
9. [Deployment Checklist](#deployment-checklist)
10. [Free Tier Optimization](#free-tier-optimization)

---

## Project Architecture

### High-Level System Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                      USER UPLOADS FILES                         │
│              (Selects Pipeline: Objects or Clothing)            │
└──────────────────────────┬──────────────────────────────────────┘
                           │
                           ▼
                  ┌────────────────────┐
                  │ Supabase Storage   │
                  │ (Raw uploads)      │
                  └────────────┬───────┘
                               │
                               ▼
                  ┌────────────────────────────┐
                  │ Create DB records (PENDING)│
                  └────────────┬───────────────┘
                               │
                               ▼
          ┌────────────────────────────────────────────────┐
          │   PIPELINE SELECTION                           │
          ├─────────────────────┬──────────────────────────┤
          │                     │                          │
          ▼                     ▼                          ▼
    ┌──────────────┐    ┌──────────────┐         ┌─────────────────┐
    │ PIPELINE A   │    │ PIPELINE B   │         │   MONITORING    │
    │ (Objects)    │    │ (Clothing)   │         │   REALTIME      │
    │              │    │              │         │                 │
    │ 1. Remove    │    │ 1. Detect    │         │ Supabase        │
    │    BG (RBG)  │    │    garment   │         │ Realtime        │
    │ 2. Generate  │    │ 2. Detect    │         │ Updates         │
    │    Pro BG    │    │    model     │         │ (Status: PENDING│
    │              │    │ 3. Overlay   │         │  -> PROCESSING  │
    └──────┬───────┘    │              │         │  -> COMPLETED)  │
           │            └──────┬───────┘         └─────────────────┘
           │                   │
           └───────────┬───────┘
                       │
                       ▼
        ┌──────────────────────────────────────┐
        │ Trigger Replicate Webhooks via API   │
        │ (Next.js API endpoints)              │
        └──────────┬───────────────────────────┘
                   │
                   ▼
        ┌──────────────────────────────────────┐
        │   REPLICATE API PROCESSES            │
        │ (Async using webhooks)               │
        └──────────┬───────────────────────────┘
                   │
                   ▼
        ┌──────────────────────────────────────┐
        │ Replicate Webhook Callback           │
        │ (Update DB: COMPLETED + result URL)  │
        └──────────┬───────────────────────────┘
                   │
                   ▼
        ┌──────────────────────────────────────┐
        │ Supabase Realtime Pushes Updates     │
        │ Frontend automatically refreshes     │
        └──────────────────────────────────────┘
```

### Data Flow Diagram

```
User Browser
    │
    ├─→ Category Selection (Objects/Clothing)
    │
    ├─→ File Upload (1-10 images)
    │
    ├─→ POST /api/upload
    │       │
    │       ├─→ Store to Supabase Storage
    │       │
    │       ├─→ Create DB rows (image_processing_jobs)
    │       │   Status: PENDING
    │       │
    │       └─→ POST /api/process-batch
    │           │
    │           ├─→ Fetch PENDING records
    │           │
    │           ├─→ For each record:
    │           │   ├─→ Call Replicate API
    │           │   ├─→ Store webhook_id
    │           │   └─→ Update Status: PROCESSING
    │           │
    │           └─→ Return job_ids
    │
    └─→ Listen to Supabase Realtime
        │
        └─→ On webhook callback:
            ├─→ POST /api/webhook/replicate
            │
            ├─→ Fetch result from Replicate
            │
            ├─→ Store result to Supabase Storage
            │
            ├─→ Update DB record
            │   Status: COMPLETED
            │   result_image_url: [URL]
            │
            └─→ Frontend sees update, displays result
```

---

## Pipeline Modes

### Pipeline A: Objects (Background Replacement)

**Purpose:** Transform raw product photos into professional images with curated backgrounds.

**Steps:**

1. **Background Removal**
   - Input: Raw product photo
   - Model: `rembg/remove-background` (Replicate)
   - Output: PNG with transparent background
   - Cost: ~$0.001 per image

2. **Professional Background Generation**
   - Input: Transparent product image + background prompt
   - Prompts: "studio lighting with marble table", "clean white studio", "minimalist workspace"
   - Model: `stability-ai/stable-diffusion-v2-inpainting` OR `openai/dall-e-3` via Replicate
   - Output: High-quality product photo with professional background
   - Cost: ~$0.05-0.10 per image

**Use Cases:**
- Footwear, electronics, accessories
- Standardize product presentation
- Create multiple style variations

**Workflow:**
```
Raw Shoe Photo
      │
      ├─→ [RBG Model] Remove Background
      │   Output: shoe_transparent.png
      │
      ├─→ [Inpaint Model] Add Professional Background
      │   Prompt: "studio lighting on marble"
      │   Output: shoe_professional.jpg
      │
      └─→ Store result_url to DB & Supabase Storage
```

---

### Pipeline B: Clothing (Virtual Try-On)

**Purpose:** Enable customers to see how garments look on selected human models.

**Steps:**

1. **Garment Detection & Extraction**
   - Input: Flat garment photo (shirt, dress, etc.)
   - Process: Crop/extract clean garment image
   - Output: Garment-only image

2. **Model Selection**
   - Pre-loaded models (5-10 diverse human poses/body types)
   - User selects model or uploads own
   - Stored in Supabase Storage (models bucket)

3. **Virtual Try-On Processing**
   - Input: Garment image + Model image
   - Model: `zarquon/fooocus-inpaint` OR `layerdiffuse/layerdiffuse` (Replicate)
   - Process: AI overlays garment onto model using pose estimation
   - Output: Realistic product-on-model visualization
   - Cost: ~$0.10-0.15 per image

**Use Cases:**
- Apparel brands (T-shirts, dresses, jackets)
- Fashion retailers
- Customer confidence improvement

**Workflow:**
```
Flat Garment Photo         Pre-stored Model Photo
          │                        │
          └────────┬───────────────┘
                   │
                   ├─→ [Virtual Try-On Model]
                   │   Process garment + model
                   │
                   └─→ Result: garment_on_model.jpg
                       Store to DB & Supabase Storage
```

---

## Database Schema

### Supabase PostgreSQL Tables

#### 1. **image_processing_jobs** (Main Job Table)

```sql
CREATE TABLE image_processing_jobs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  pipeline_mode TEXT NOT NULL CHECK (pipeline_mode IN ('objects', 'clothing')),
  
  -- Input references
  input_image_url TEXT NOT NULL,
  secondary_image_url TEXT,  -- For clothing: model photo
  
  -- Processing tracking
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  webhook_id TEXT,  -- Replicate webhook ID for tracking
  
  -- Output
  result_image_url TEXT,
  error_message TEXT,
  
  -- Metadata
  input_storage_path TEXT,  -- e.g., "uploads/user123/image1.jpg"
  batch_id UUID REFERENCES image_batches(id),
  processing_parameters JSONB,  -- Store pipeline-specific params
  
  -- Timestamps
  created_at TIMESTAMP DEFAULT NOW(),
  started_at TIMESTAMP,
  completed_at TIMESTAMP,
  
  -- Performance
  processing_time_seconds INT,
  replicate_run_id TEXT
);

CREATE INDEX idx_user_pipeline ON image_processing_jobs(user_id, pipeline_mode);
CREATE INDEX idx_status_batch ON image_processing_jobs(status, batch_id);
```

#### 2. **image_batches** (Batch Grouping)

```sql
CREATE TABLE image_batches (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  batch_name TEXT NOT NULL,
  pipeline_mode TEXT NOT NULL CHECK (pipeline_mode IN ('objects', 'clothing')),
  
  -- Batch stats
  total_images INT NOT NULL,
  completed_count INT DEFAULT 0,
  failed_count INT DEFAULT 0,
  
  status TEXT DEFAULT 'processing' CHECK (status IN ('processing', 'completed', 'failed', 'cancelled')),
  
  created_at TIMESTAMP DEFAULT NOW(),
  completed_at TIMESTAMP,
  
  -- Metadata
  batch_metadata JSONB  -- Store batch-level settings
);

CREATE INDEX idx_user_batches ON image_batches(user_id, created_at DESC);
```

#### 3. **processing_models** (Pre-trained Models Registry)

```sql
CREATE TABLE processing_models (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  
  model_name TEXT NOT NULL UNIQUE,
  pipeline_type TEXT NOT NULL CHECK (pipeline_type IN ('background_removal', 'background_generation', 'virtual_tryon')),
  
  -- Replicate reference
  replicate_owner TEXT NOT NULL,
  replicate_model_name TEXT NOT NULL,
  replicate_version_id TEXT,
  
  -- Configuration
  input_schema JSONB,  -- Expected input parameters
  cost_per_run DECIMAL(10, 5),
  avg_run_time_seconds INT,
  
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW(),
  updated_at TIMESTAMP DEFAULT NOW()
);
```

#### 4. **user_model_uploads** (Clothing Pipeline: Custom Models)

```sql
CREATE TABLE user_model_uploads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  model_image_url TEXT NOT NULL,
  storage_path TEXT NOT NULL,
  model_description TEXT,
  
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP DEFAULT NOW(),
  
  UNIQUE(user_id, storage_path)
);
```

### Storage Structure (Supabase Storage)

```
supabase-storage/
├── uploads/
│   └── {user_id}/
│       └── raw/{batch_id}/
│           ├── image_1.jpg
│           ├── image_2.jpg
│           └── ...
│
├── results/
│   └── {user_id}/
│       └── processed/{batch_id}/
│           ├── image_1_result.jpg
│           ├── image_2_result.jpg
│           └── ...
│
└── models/
    └── {user_id}/
        ├── model_photo_1.jpg (For clothing pipeline)
        └── model_photo_2.jpg
```

---

## Batch Processing Architecture

### Batch Processing Flow

#### Phase 1: Upload & Queue

```javascript
// User uploads 5 images for Objects pipeline

POST /api/upload
├── Validate files (size, type)
├── Create batch record (status: processing, total_images: 5)
├── For each file:
│   ├── Upload to Supabase Storage (uploads/{user_id}/raw/{batch_id}/)
│   ├── Create image_processing_jobs row (status: pending)
│   └── Store metadata (input_storage_path, batch_id)
└── Return batch_id

Response:
{
  batch_id: "uuid-1234",
  total_images: 5,
  status: "processing"
}
```

#### Phase 2: Trigger Processing

```javascript
POST /api/process-batch
├── Input: batch_id, pipeline_mode, processing_params
├── Fetch all PENDING records for batch
├── For each record:
│   ├── Determine which Replicate models to use
│   ├── Fetch input image URL (signed URL from Supabase)
│   ├── Call Replicate API with webhook URL
│   │   Example: replicate.predictions.create({
│   │     model: "rembg/remove-background",
│   │     input: { image: signed_url },
│   │     webhook: "https://yourdomain.com/api/webhook/replicate",
│   │     webhook_events_filter: ["completed"]
│   │   })
│   ├── Store webhook_id & replicate_run_id
│   ├── Update status: processing
│   ├── Update started_at timestamp
│   └── Log: "Batch {batch_id} processing started"
└── Return job summary

Response:
{
  batch_id: "uuid-1234",
  jobs_started: 5,
  estimated_completion: "2026-02-12T20:15:00Z"
}
```

#### Phase 3: Webhook Callback (Async)

```javascript
POST /api/webhook/replicate
├── Receive webhook from Replicate (when processing completes)
│   Payload: {
│     id: "webhook-uuid",
│     status: "completed",
│     result: {
│       output: ["https://replicate.com/output/..."],
│       error: null
│     }
│   }
├── Validate webhook signature (Replicate header)
├── Find image_processing_job by webhook_id
├── If status === "completed":
│   ├── Fetch output from Replicate (result.output[0])
│   ├── Download output image
│   ├── Upload to Supabase Storage (results/{user_id}/processed/{batch_id}/)
│   ├── Update DB record:
│   │   - result_image_url: new Supabase URL
│   │   - status: "completed"
│   │   - completed_at: NOW()
│   │   - processing_time_seconds: (completed_at - started_at)
│   └── Update batch stats (completed_count++)
├── If error:
│   ├── Update DB record:
│   │   - status: "failed"
│   │   - error_message: error details
│   └── Update batch stats (failed_count++)
└── Database change triggers Supabase Realtime update
    (Frontend subscription receives update)
```

### Real-time Frontend Updates

```javascript
// Frontend listens to Supabase Realtime

useEffect(() => {
  const subscription = supabase
    .channel(`batch:${batchId}`)
    .on(
      'postgres_changes',
      {
        event: '*',
        schema: 'public',
        table: 'image_processing_jobs',
        filter: `batch_id=eq.${batchId}`
      },
      (payload) => {
        // Update UI: show result image or error
        setJob(payload.new);
      }
    )
    .subscribe();

  return () => supabase.removeAllChannels();
}, [batchId]);
```

---

## API Endpoints

### Authentication Flow

All endpoints require Supabase JWT authentication. Use Next.js middleware to verify tokens.

```
Authorization: Bearer {supabase_jwt}
```

### 1. Upload Endpoint

```
POST /api/upload
Content-Type: multipart/form-data

Body:
- files: File[] (1-10 images)
- pipeline_mode: "objects" | "clothing"
- batch_name: string (optional)
- secondary_file: File (for clothing pipeline - model photo)

Response: 201 Created
{
  batch_id: "uuid-1234",
  total_images: 5,
  uploaded_at: "2026-02-12T20:00:00Z",
  message: "Images queued for processing"
}

Error: 400 Bad Request
{
  error: "File too large (max 10MB per image)",
  code: "FILE_SIZE_EXCEEDED"
}

Error: 401 Unauthorized
{
  error: "Invalid authentication token"
}
```

### 2. Process Batch Endpoint

```
POST /api/process-batch
Content-Type: application/json

Body:
{
  batch_id: "uuid-1234",
  pipeline_mode: "objects" | "clothing",
  processing_params: {
    // Objects pipeline:
    background_prompt?: "studio lighting on marble table"
    
    // Clothing pipeline:
    model_id?: "uuid-5678"  // Pre-selected model
  }
}

Response: 202 Accepted
{
  batch_id: "uuid-1234",
  jobs_started: 5,
  status: "processing",
  webhook_url: "https://yourdomain.com/api/webhook/replicate",
  estimated_completion: "2026-02-12T20:15:00Z"
}
```

### 3. Get Batch Status

```
GET /api/batches/{batch_id}

Response: 200 OK
{
  batch_id: "uuid-1234",
  batch_name: "Product Photos - Feb 2026",
  pipeline_mode: "objects",
  total_images: 5,
  completed: 3,
  processing: 2,
  failed: 0,
  status: "processing",
  jobs: [
    {
      id: "uuid-job-1",
      status: "completed",
      input_image_url: "...",
      result_image_url: "...",
      completed_at: "2026-02-12T20:03:00Z"
    },
    {
      id: "uuid-job-2",
      status: "processing",
      input_image_url: "...",
      started_at: "2026-02-12T20:01:00Z"
    }
  ]
}
```

### 4. Download Results

```
GET /api/results/{batch_id}?format=zip|json

Response: 200 OK (application/zip or application/json)
- ZIP: Compressed folder with all result images
- JSON: Metadata with download URLs
```

### 5. Webhook Endpoint (Replicate Callback)

```
POST /api/webhook/replicate
Content-Type: application/json
X-Replicate-Webhook-Secret: {signature}

Body (from Replicate):
{
  id: "webhook-uuid",
  prediction_id: "urn:replicate:prediction:abc123",
  status: "succeeded",
  result: {
    output: ["https://replicate.com/api/models/output/abc123.jpg"]
  }
}

Response: 200 OK
{
  processed: true,
  job_id: "uuid-job-1",
  result_stored: true
}

Note: Webhook signature must be validated:
- Replicate sends X-Replicate-Webhook-Secret header
- Verify against REPLICATE_WEBHOOK_SECRET env var
```

---

## Implementation Workflow

### Week 1: Foundation & Setup

#### Day 1-2: Project Setup

```bash
# Initialize Next.js 16 project
npx create-next-app@16 ai-photo-augmentation
cd ai-photo-augmentation

# Install dependencies
npm install @supabase/supabase-js replicate dotenv next-middleware

# Setup environment
cp .env.example .env.local
```

**.env.local:**
```
NEXT_PUBLIC_SUPABASE_URL=https://xxxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=xxxxx
SUPABASE_SERVICE_ROLE_KEY=xxxxx

REPLICATE_API_TOKEN=xxxxx
REPLICATE_WEBHOOK_SECRET=xxxxx

NEXT_PUBLIC_API_URL=http://localhost:3000 (dev) or yourdomain.com (prod)
```

#### Day 3-4: Database Setup

```sql
-- Run in Supabase SQL Editor

-- Create tables (see Database Schema section)

-- Create RLS policies
ALTER TABLE image_processing_jobs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users see own jobs"
  ON image_processing_jobs FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users create own jobs"
  ON image_processing_jobs FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Create storage buckets
-- Via Supabase dashboard:
-- - uploads (public: false)
-- - results (public: true, for download)
-- - models (public: false)
```

#### Day 5: Authentication Middleware

```typescript
// middleware.ts
import { createServerClient } from "@supabase/ssr";
import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export async function middleware(request: NextRequest) {
  let response = NextResponse.next({
    request: {
      headers: request.headers,
    },
  });

  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return request.cookies.getAll();
        },
        setAll(cookiesToSet) {
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const { data: { user } } = await supabase.auth.getUser();

  // Redirect unauthenticated users to login
  if (!user && request.nextUrl.pathname.startsWith("/app")) {
    return NextResponse.redirect(new URL("/auth/login", request.url));
  }

  return response;
}

export const config = {
  matcher: ["/app/:path*", "/api/:path*"],
};
```

---

### Week 2: Core API Endpoints

#### Day 1-2: Upload & Batch Creation

```typescript
// app/api/upload/route.ts

import { createServerClient } from "@supabase/ssr";
import { NextRequest, NextResponse } from "next/server";
import { v4 as uuidv4 } from "uuid";

export async function POST(request: NextRequest) {
  try {
    // Get auth user
    const supabase = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!,
      { cookies: { getAll: () => [] } }
    );

    const { data: { user } } = await supabase.auth.getUser(
      request.headers.get("authorization")?.split(" ")[1] || ""
    );

    if (!user) return NextResponse.json({ error: "Unauthorized" }, { status: 401 });

    // Parse form data
    const formData = await request.formData();
    const files = formData.getAll("files") as File[];
    const pipeline_mode = formData.get("pipeline_mode") as string;
    const batch_name = formData.get("batch_name") as string || `Batch ${new Date().toLocaleDateString()}`;

    // Validate
    if (!files.length || !pipeline_mode) {
      return NextResponse.json(
        { error: "Missing files or pipeline_mode" },
        { status: 400 }
      );
    }

    if (files.length > 10) {
      return NextResponse.json(
        { error: "Maximum 10 files per batch" },
        { status: 400 }
      );
    }

    // Create batch record
    const batch_id = uuidv4();
    const { error: batchError } = await supabase
      .from("image_batches")
      .insert({
        id: batch_id,
        user_id: user.id,
        batch_name,
        pipeline_mode,
        total_images: files.length,
      });

    if (batchError) throw batchError;

    // Upload files & create job records
    for (const file of files) {
      const file_id = uuidv4();
      const storage_path = `uploads/${user.id}/raw/${batch_id}/${file.name}`;

      // Upload to Supabase Storage
      const { error: uploadError } = await supabase.storage
        .from("uploads")
        .upload(storage_path, file, { upsert: false });

      if (uploadError) {
        console.error("Storage upload error:", uploadError);
        continue; // Skip failed file
      }

      // Create job record
      const { error: jobError } = await supabase
        .from("image_processing_jobs")
        .insert({
          user_id: user.id,
          batch_id,
          pipeline_mode,
          input_storage_path: storage_path,
          input_image_url: `${process.env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/public/uploads/${storage_path}`,
          status: "pending",
        });

      if (jobError) console.error("Job creation error:", jobError);
    }

    return NextResponse.json(
      {
        batch_id,
        total_images: files.length,
        message: "Images uploaded successfully",
      },
      { status: 201 }
    );
  } catch (error) {
    console.error("Upload error:", error);
    return NextResponse.json(
      { error: "Upload failed" },
      { status: 500 }
    );
  }
}
```

#### Day 3: Process Batch Endpoint

```typescript
// app/api/process-batch/route.ts

import Replicate from "replicate";
import { createServerClient } from "@supabase/ssr";
import { NextRequest, NextResponse } from "next/server";

const replicate = new Replicate({
  auth: process.env.REPLICATE_API_TOKEN!,
});

export async function POST(request: NextRequest) {
  try {
    const supabase = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!,
      { cookies: { getAll: () => [] } }
    );

    const body = await request.json();
    const { batch_id, pipeline_mode, processing_params } = body;

    // Get all pending jobs for batch
    const { data: jobs, error: fetchError } = await supabase
      .from("image_processing_jobs")
      .select("*")
      .eq("batch_id", batch_id)
      .eq("status", "pending");

    if (fetchError) throw fetchError;

    // Process each job
    for (const job of jobs) {
      try {
        let prediction;

        if (pipeline_mode === "objects") {
          // Pipeline A: Background removal + professional background
          // Step 1: Remove background
          prediction = await replicate.predictions.create({
            model: "rembg/remove-background",
            input: {
              image: job.input_image_url,
            },
            webhook: `${process.env.NEXT_PUBLIC_API_URL}/api/webhook/replicate`,
            webhook_events_filter: ["completed"],
          });

          // Store checkpoint for step 2 (handled in webhook)
          await supabase
            .from("image_processing_jobs")
            .update({
              webhook_id: prediction.id,
              replicate_run_id: prediction.id,
              status: "processing",
              started_at: new Date().toISOString(),
              processing_parameters: {
                step: 1,
                background_prompt: processing_params?.background_prompt,
              },
            })
            .eq("id", job.id);
        } else if (pipeline_mode === "clothing") {
          // Pipeline B: Virtual try-on
          const { data: model } = await supabase
            .from("user_model_uploads")
            .select("model_image_url")
            .eq("id", processing_params?.model_id)
            .single();

          prediction = await replicate.predictions.create({
            model: "zarquon/fooocus-inpaint",
            input: {
              image_upload: job.input_image_url,
              prompt: "realistic clothing on model",
              reference_image: model?.model_image_url,
            },
            webhook: `${process.env.NEXT_PUBLIC_API_URL}/api/webhook/replicate`,
            webhook_events_filter: ["completed"],
          });

          await supabase
            .from("image_processing_jobs")
            .update({
              webhook_id: prediction.id,
              replicate_run_id: prediction.id,
              status: "processing",
              started_at: new Date().toISOString(),
              secondary_image_url: model?.model_image_url,
            })
            .eq("id", job.id);
        }
      } catch (error) {
        console.error(`Job ${job.id} processing error:`, error);
        await supabase
          .from("image_processing_jobs")
          .update({
            status: "failed",
            error_message: String(error),
          })
          .eq("id", job.id);
      }
    }

    return NextResponse.json(
      {
        batch_id,
        jobs_started: jobs.length,
        message: "Batch processing started",
      },
      { status: 202 }
    );
  } catch (error) {
    console.error("Process batch error:", error);
    return NextResponse.json(
      { error: "Processing failed" },
      { status: 500 }
    );
  }
}
```

#### Day 4-5: Webhook Handler

```typescript
// app/api/webhook/replicate/route.ts

import { createServerClient } from "@supabase/ssr";
import { NextRequest, NextResponse } from "next/server";
import crypto from "crypto";

export async function POST(request: NextRequest) {
  try {
    // Validate webhook signature
    const signature = request.headers.get("x-replicate-webhook-secret");
    const body = await request.text();
    const hash = crypto
      .createHmac("sha256", process.env.REPLICATE_WEBHOOK_SECRET!)
      .update(body)
      .digest("hex");

    if (hash !== signature) {
      console.warn("Invalid webhook signature");
      return NextResponse.json({ error: "Invalid signature" }, { status: 401 });
    }

    const payload = JSON.parse(body);
    const { id, status, result, error: replicateError } = payload;

    const supabase = createServerClient(
      process.env.NEXT_PUBLIC_SUPABASE_URL!,
      process.env.SUPABASE_SERVICE_ROLE_KEY!,
      { cookies: { getAll: () => [] } }
    );

    // Find job by webhook_id
    const { data: job, error: fetchError } = await supabase
      .from("image_processing_jobs")
      .select("*")
      .eq("webhook_id", id)
      .single();

    if (fetchError || !job) {
      console.error("Job not found for webhook:", id);
      return NextResponse.json({ error: "Job not found" }, { status: 404 });
    }

    if (status === "succeeded" && result?.output) {
      // Download result image from Replicate
      const resultUrl = Array.isArray(result.output)
        ? result.output[0]
        : result.output;
      const imageResponse = await fetch(resultUrl);
      const imageBuffer = await imageResponse.arrayBuffer();

      // Upload to Supabase Storage
      const resultStoragePath = `results/${job.user_id}/processed/${job.batch_id}/${Date.now()}.jpg`;
      const { error: uploadError } = await supabase.storage
        .from("results")
        .upload(
          resultStoragePath,
          imageBuffer,
          { contentType: "image/jpeg", upsert: false }
        );

      if (uploadError) throw uploadError;

      // Get signed URL
      const { data: signedUrlData } = await supabase.storage
        .from("results")
        .createSignedUrl(resultStoragePath, 60 * 60 * 24 * 365); // 1 year

      // Update job
      const completedAt = new Date();
      const startedAt = new Date(job.started_at);
      const processingTime = Math.round(
        (completedAt.getTime() - startedAt.getTime()) / 1000
      );

      const { error: updateError } = await supabase
        .from("image_processing_jobs")
        .update({
          status: "completed",
          result_image_url: signedUrlData?.signedUrl,
          completed_at: completedAt.toISOString(),
          processing_time_seconds: processingTime,
        })
        .eq("id", job.id);

      if (updateError) throw updateError;

      // Update batch stats
      const { data: batch } = await supabase
        .from("image_batches")
        .select("completed_count, total_images")
        .eq("id", job.batch_id)
        .single();

      const newCompletedCount = (batch?.completed_count || 0) + 1;
      const isComplete = newCompletedCount === batch?.total_images;

      await supabase
        .from("image_batches")
        .update({
          completed_count: newCompletedCount,
          status: isComplete ? "completed" : "processing",
          completed_at: isComplete ? new Date().toISOString() : null,
        })
        .eq("id", job.batch_id);
    } else if (status === "failed" || replicateError) {
      await supabase
        .from("image_processing_jobs")
        .update({
          status: "failed",
          error_message: replicateError || "Processing failed",
          completed_at: new Date().toISOString(),
        })
        .eq("id", job.id);

      // Update batch failure count
      const { data: batch } = await supabase
        .from("image_batches")
        .select("failed_count")
        .eq("id", job.batch_id)
        .single();

      await supabase
        .from("image_batches")
        .update({
          failed_count: (batch?.failed_count || 0) + 1,
        })
        .eq("id", job.batch_id);
    }

    return NextResponse.json(
      { processed: true, job_id: job.id },
      { status: 200 }
    );
  } catch (error) {
    console.error("Webhook error:", error);
    return NextResponse.json(
      { error: "Webhook processing failed" },
      { status: 500 }
    );
  }
}
```

---

### Week 3: Frontend Components

#### Day 1-2: Upload Component

```typescript
// app/components/UploadForm.tsx

"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createBrowserClient } from "@supabase/ssr";

type PipelineMode = "objects" | "clothing";

export function UploadForm() {
  const [pipeline, setPipeline] = useState<PipelineMode>("objects");
  const [files, setFiles] = useState<File[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();

  const supabase = createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    if (e.target.files) {
      setFiles(Array.from(e.target.files));
    }
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setIsLoading(true);
    setError(null);

    try {
      const {
        data: { user },
      } = await supabase.auth.getUser();
      if (!user) throw new Error("Not authenticated");

      const token = (await supabase.auth.getSession()).data.session?.access_token;

      const formData = new FormData();
      files.forEach((file) => formData.append("files", file));
      formData.append("pipeline_mode", pipeline);

      const response = await fetch("/api/upload", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
        },
        body: formData,
      });

      if (!response.ok) throw new Error("Upload failed");

      const { batch_id } = await response.json();
      router.push(`/app/batch/${batch_id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Upload failed");
    } finally {
      setIsLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="max-w-md mx-auto p-6 space-y-6">
      <div>
        <label className="block text-sm font-medium mb-2">Pipeline</label>
        <select
          value={pipeline}
          onChange={(e) => setPipeline(e.target.value as PipelineMode)}
          className="w-full px-3 py-2 border rounded-md"
        >
          <option value="objects">Objects (Background Replacement)</option>
          <option value="clothing">Clothing (Virtual Try-On)</option>
        </select>
      </div>

      <div>
        <label className="block text-sm font-medium mb-2">Upload Images</label>
        <input
          type="file"
          multiple
          accept="image/*"
          onChange={handleFileChange}
          className="w-full"
          disabled={isLoading}
        />
        <p className="text-xs text-gray-500 mt-1">
          Max 10 images, 10MB each
        </p>
      </div>

      {files.length > 0 && (
        <div className="text-sm">
          <p className="font-medium">{files.length} file(s) selected</p>
          <ul className="mt-2 space-y-1">
            {files.map((f) => (
              <li key={f.name} className="text-gray-600">
                {f.name} ({(f.size / 1024 / 1024).toFixed(2)}MB)
              </li>
            ))}
          </ul>
        </div>
      )}

      {error && <div className="text-red-500 text-sm">{error}</div>}

      <button
        type="submit"
        disabled={!files.length || isLoading}
        className="w-full px-4 py-2 bg-blue-500 text-white rounded-md disabled:opacity-50"
      >
        {isLoading ? "Uploading..." : "Upload & Process"}
      </button>
    </form>
  );
}
```

#### Day 3-4: Batch Monitor Component

```typescript
// app/components/BatchMonitor.tsx

"use client";

import { useEffect, useState } from "react";
import { createBrowserClient } from "@supabase/ssr";
import Image from "next/image";
import { RealtimePostgresInsertPayload } from "@supabase/realtime-js";

type Job = {
  id: string;
  status: "pending" | "processing" | "completed" | "failed";
  input_image_url: string;
  result_image_url: string | null;
  error_message: string | null;
  processing_time_seconds: number | null;
  completed_at: string | null;
};

export function BatchMonitor({ batchId }: { batchId: string }) {
  const [jobs, setJobs] = useState<Job[]>([]);
  const [batch, setBatch] = useState<{
    total_images: number;
    completed_count: number;
    failed_count: number;
    status: string;
  } | null>(null);
  const [loading, setLoading] = useState(true);

  const supabase = createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );

  // Initial load
  useEffect(() => {
    const loadData = async () => {
      try {
        // Fetch batch info
        const { data: batchData } = await supabase
          .from("image_batches")
          .select("total_images, completed_count, failed_count, status")
          .eq("id", batchId)
          .single();

        setBatch(batchData);

        // Fetch jobs
        const { data: jobsData } = await supabase
          .from("image_processing_jobs")
          .select("*")
          .eq("batch_id", batchId);

        setJobs(jobsData || []);
      } catch (error) {
        console.error("Load error:", error);
      } finally {
        setLoading(false);
      }
    };

    loadData();
  }, [batchId]);

  // Real-time subscription
  useEffect(() => {
    const subscription = supabase
      .channel(`batch:${batchId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "image_processing_jobs",
          filter: `batch_id=eq.${batchId}`,
        },
        (payload: RealtimePostgresInsertPayload<Job>) => {
          if (payload.eventType === "UPDATE") {
            setJobs((prev) =>
              prev.map((j) =>
                j.id === payload.new.id ? payload.new : j
              )
            );
          }
        }
      )
      .subscribe();

    return () => {
      supabase.removeAllChannels();
    };
  }, [batchId]);

  if (loading) return <div className="text-center py-12">Loading...</div>;

  const progressPercent = batch
    ? ((batch.completed_count + batch.failed_count) / batch.total_images) * 100
    : 0;

  return (
    <div className="space-y-8">
      {/* Batch Summary */}
      {batch && (
        <div className="bg-white p-6 rounded-lg shadow">
          <h2 className="text-lg font-semibold mb-4">Batch Progress</h2>
          <div className="grid grid-cols-4 gap-4 mb-4">
            <div>
              <p className="text-gray-600 text-sm">Total</p>
              <p className="text-2xl font-bold">{batch.total_images}</p>
            </div>
            <div>
              <p className="text-gray-600 text-sm">Completed</p>
              <p className="text-2xl font-bold text-green-500">
                {batch.completed_count}
              </p>
            </div>
            <div>
              <p className="text-gray-600 text-sm">Processing</p>
              <p className="text-2xl font-bold text-blue-500">
                {batch.total_images -
                  batch.completed_count -
                  batch.failed_count}
              </p>
            </div>
            <div>
              <p className="text-gray-600 text-sm">Failed</p>
              <p className="text-2xl font-bold text-red-500">
                {batch.failed_count}
              </p>
            </div>
          </div>
          <div className="w-full bg-gray-200 rounded-full h-2">
            <div
              className="bg-blue-500 h-2 rounded-full transition-all"
              style={{ width: `${progressPercent}%` }}
            />
          </div>
        </div>
      )}

      {/* Job Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {jobs.map((job) => (
          <div
            key={job.id}
            className="bg-white p-4 rounded-lg shadow overflow-hidden"
          >
            {/* Input Image */}
            <div className="relative h-40 bg-gray-100 rounded-md overflow-hidden mb-3">
              <Image
                src={job.input_image_url}
                alt="Input"
                fill
                className="object-cover"
              />
            </div>

            {/* Status */}
            <div className="mb-3">
              <span
                className={`inline-block px-3 py-1 text-xs rounded-full ${
                  job.status === "completed"
                    ? "bg-green-100 text-green-800"
                    : job.status === "processing"
                      ? "bg-blue-100 text-blue-800"
                      : job.status === "failed"
                        ? "bg-red-100 text-red-800"
                        : "bg-gray-100 text-gray-800"
                }`}
              >
                {job.status.charAt(0).toUpperCase() + job.status.slice(1)}
              </span>
              {job.processing_time_seconds && (
                <p className="text-xs text-gray-500 mt-1">
                  {job.processing_time_seconds}s
                </p>
              )}
            </div>

            {/* Result */}
            {job.status === "completed" && job.result_image_url ? (
              <div className="relative h-40 bg-gray-100 rounded-md overflow-hidden mb-3">
                <Image
                  src={job.result_image_url}
                  alt="Result"
                  fill
                  className="object-cover"
                />
              </div>
            ) : job.status === "failed" ? (
              <div className="bg-red-50 p-3 rounded-md text-xs text-red-700">
                {job.error_message || "Processing failed"}
              </div>
            ) : null}

            {/* Download Button */}
            {job.status === "completed" && job.result_image_url && (
              <a
                href={job.result_image_url}
                download
                className="block w-full text-center px-3 py-2 bg-blue-500 text-white text-sm rounded-md hover:bg-blue-600"
              >
                Download
              </a>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
```

---

## Error Handling & Monitoring

### Common Error Scenarios

| Scenario | Response | Handling |
|----------|----------|----------|
| **File too large** | 413 Payload Too Large | Display user message, split into smaller batches |
| **Invalid image format** | 400 Bad Request | Validate file type client-side |
| **Replicate API down** | 503 Service Unavailable | Retry with exponential backoff (3 retries) |
| **Webhook timeout** | Database remains `processing` | Manual retry button or 24-hour timeout cleanup |
| **Storage quota exceeded** | 507 Insufficient Storage | Implement file cleanup (delete old results after 30 days) |
| **Rate limit exceeded** | 429 Too Many Requests | Queue batches, implement rate limiting per user |

### Monitoring & Logging

```typescript
// app/lib/logging.ts

export async function logEvent(
  event: string,
  data: Record<string, any>,
  level: "info" | "warn" | "error" = "info"
) {
  const timestamp = new Date().toISOString();
  const logEntry = {
    timestamp,
    level,
    event,
    ...data,
  };

  // Log to console in development
  if (process.env.NODE_ENV === "development") {
    console.log(`[${level.toUpperCase()}] ${event}`, data);
  }

  // Optional: Send to external service (e.g., Sentry, LogRocket)
  if (process.env.SENTRY_DSN) {
    // Integration with Sentry
  }

  // Store in Supabase (optional analytics table)
  // const supabase = createServerClient(...);
  // await supabase.from("activity_logs").insert(logEntry);
}
```

### Health Check Endpoint

```typescript
// app/api/health/route.ts

export async function GET() {
  const checks = {
    supabase: false,
    replicate: false,
    timestamp: new Date().toISOString(),
  };

  try {
    // Test Supabase
    const supabase = createServerClient(...);
    await supabase.auth.getSession();
    checks.supabase = true;
  } catch {
    checks.supabase = false;
  }

  try {
    // Test Replicate
    const response = await fetch("https://api.replicate.com/v1/models", {
      headers: { Authorization: `Token ${process.env.REPLICATE_API_TOKEN}` },
    });
    checks.replicate = response.ok;
  } catch {
    checks.replicate = false;
  }

  const allHealthy = Object.values(checks).slice(0, -1).every(Boolean);

  return Response.json(checks, {
    status: allHealthy ? 200 : 503,
  });
}
```

---

## Deployment Checklist

### Pre-Deployment

- [ ] Environment variables set in Vercel dashboard
- [ ] Supabase database backups configured
- [ ] Replicate API token validated
- [ ] Webhook URL whitelisted in Replicate
- [ ] Storage buckets created with correct permissions
- [ ] RLS policies tested
- [ ] Batch size limits tested (e.g., 10 images max)
- [ ] Error scenarios tested (network failures, timeouts)

### Deployment Steps

```bash
# 1. Run tests
npm run test

# 2. Build
npm run build

# 3. Deploy to Vercel
vercel deploy

# 4. Verify deployment
curl https://yourdomain.com/api/health

# 5. Monitor logs
vercel logs -f
```

### Post-Deployment

- [ ] Test upload flow end-to-end
- [ ] Monitor Replicate API usage
- [ ] Check Supabase storage quota
- [ ] Verify webhook callbacks working
- [ ] Test real-time updates
- [ ] Check error logs for issues

---

## Free Tier Optimization

### Vercel Limits

- **Function execution timeout:** 10 seconds (serverless)
  - **Solution:** Use webhooks for async processing (Replicate handles this)
- **Bundle size:** 50MB
  - **Solution:** Tree-shake dependencies, use dynamic imports
- **Concurrent functions:** 12
  - **Solution:** Queue long-running jobs, use Replicate async

### Supabase Limits

- **Storage:** 1GB free
  - **Solution:** Implement cleanup (delete results after 30 days)
- **Database rows:** Unlimited
  - **Solution:** Archive old batches monthly
- **Realtime connections:** 1
  - **Solution:** Share single connection, multiple subscriptions
- **Auth users:** Unlimited
  - **Solution:** JWT-based auth is free

### Replicate Limits

- **API calls:** Free tier ($0 with credits), then ~$0.001-0.15 per run
  - **Solution:** Start with free credits ($20/month), monitor usage
- **No concurrent predictions limit** for free tier
  - **Solution:** Can queue multiple jobs simultaneously

### Cost Estimation (Free Tier)

```
Monthly Processing (estimate):
- 100 Objects batches × 5 images = 500 runs × $0.05 = $25
- 100 Clothing batches × 3 images = 300 runs × $0.10 = $30
- Total: ~$55/month with paid Replicate

Free tier: Start with Replicate $20 credits
Scaling: Add Vercel Pro ($20/mo) + Supabase Pro ($25/mo) at ~1000+ batches/month
```

### Performance Optimization

```typescript
// Image compression before upload
import imageCompression from "browser-image-compression";

const options = {
  maxSizeMB: 1,
  maxWidthOrHeight: 1920,
  useWebWorker: true,
};

const compressedFile = await imageCompression(file, options);
```

---

## Implementation Timeline

**Total: 3 weeks (junior developer)**

- **Week 1:** Foundation & setup (5 days)
- **Week 2:** Core API endpoints (5 days)
- **Week 3:** Frontend UI & deployment (5 days)

**Maintenance after launch:**
- Monitor webhooks (daily)
- Check Replicate costs (weekly)
- Review errors (daily)
- Cleanup old data (monthly)

---

## Key Moving Parts (Minimized)

| Component | Complexity | Reason |
|-----------|-----------|--------|
| **Supabase Auth** | Low | JWT-based, built-in |
| **Next.js API** | Low | Simple route handlers |
| **Replicate API** | Medium | Async webhooks, but clear docs |
| **Supabase Realtime** | Low | Built-in pub/sub |
| **Database Schema** | Low | 4 tables, simple relations |
| **Frontend** | Low | React components + hooks |

---

## Next Steps

1. **Start with Week 1 setup** - Get authentication and database schema complete
2. **Build API endpoints** - Upload, process-batch, webhook handler
3. **Create simple UI** - Upload form + batch monitor
4. **Test with 5-10 images** - Verify entire pipeline works
5. **Deploy to Vercel** - Configure environment variables
6. **Monitor & iterate** - Fix bugs, optimize performance
7. **Expand features** - Add more background prompts, model variations, result filters

---

**Document Version:** 1.0  
**Last Updated:** February 2026  
**Maintainer:** Junior Developer  
**Status:** Ready for Implementation
