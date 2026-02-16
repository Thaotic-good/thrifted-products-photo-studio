# BE_EXECUTION.md
## Backend Implementation Guide - AI Product Photography Augmentation

> **Note for AI Assistants:** This document is designed to be modified by AI agents. Update code examples, add new sections, refactor implementations, or expand on any technical details as needed. Maintain code quality and follow Next.js 16 + Supabase best practices.

---

## Document Overview

This is the **detailed backend implementation guide** for the AI Product Photography Augmentation project. This document covers:
- Next.js 16 API Routes
- Supabase Database & Storage
- Replicate API Integration
- Webhook Handling
- Authentication & Middleware
- Error Handling & Logging

**Related Documents:**
- [EXECUTION_PLAN.md](./EXECUTION_PLAN.md) - Master project overview
- [FE_EXECUTION.md](./FE_EXECUTION.md) - Frontend implementation guide

---

## Table of Contents

1. [Project Setup](#1-project-setup)
2. [Supabase Configuration](#2-supabase-configuration)
3. [Database Schema](#3-database-schema)
4. [Storage Structure](#4-storage-structure)
5. [Authentication Middleware](#5-authentication-middleware)
6. [Replicate API Integration](#6-replicate-api-integration)
7. [API Endpoint: Upload](#7-api-endpoint-upload)
8. [API Endpoint: Process Batch](#8-api-endpoint-process-batch)
9. [API Endpoint: Webhook Handler](#9-api-endpoint-webhook-handler)
10. [API Endpoint: Batch Status](#10-api-endpoint-batch-status)
11. [Error Handling](#11-error-handling)
12. [Logging & Monitoring](#12-logging--monitoring)
13. [Testing](#13-testing)
14. [Deployment](#14-deployment)
15. [Performance Optimization](#15-performance-optimization)

---

## 1. Project Setup

### 1.1 Initialize Next.js 16 Project

```bash
# Create new Next.js project
npx create-next-app@16 ai-photo-augmentation --typescript --tailwind --app

cd ai-photo-augmentation
```

### 1.2 Install Dependencies

```bash
# Core dependencies
npm install @supabase/supabase-js @supabase/ssr replicate

# Utilities
npm install uuid crypto-js

# Development
npm install -D @types/node @types/uuid

# Testing
npm install -D jest @testing-library/react @testing-library/jest-dom supertest
```

### 1.3 Environment Variables

Create `.env.local`:

```bash
# Supabase
NEXT_PUBLIC_SUPABASE_URL=https://xxxxx.supabase.co
NEXT_PUBLIC_SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...

# Replicate
REPLICATE_API_TOKEN=r8_xxxxxxxxxxxxxxxxxxxxxxxxxxxxx
REPLICATE_WEBHOOK_SECRET=whsec_xxxxxxxxxxxxxxxxxxxxx

# Application
NEXT_PUBLIC_API_URL=http://localhost:3000
NODE_ENV=development

# Optional: Error tracking
SENTRY_DSN=https://xxxxx@sentry.io/xxxxx
```

Create `.env.example`:

```bash
# Supabase
NEXT_PUBLIC_SUPABASE_URL=your_supabase_url
NEXT_PUBLIC_SUPABASE_ANON_KEY=your_anon_key
SUPABASE_SERVICE_ROLE_KEY=your_service_role_key

# Replicate
REPLICATE_API_TOKEN=your_replicate_token
REPLICATE_WEBHOOK_SECRET=your_webhook_secret

# Application
NEXT_PUBLIC_API_URL=your_api_url
NODE_ENV=development
```

### 1.4 Project Structure

```
app/
├── api/
│   ├── upload/
│   │   └── route.ts
│   ├── process-batch/
│   │   └── route.ts
│   ├── batches/
│   │   └── [id]/
│   │       └── route.ts
│   ├── webhook/
│   │   └── replicate/
│   │       └── route.ts
│   ├── results/
│   │   └── [id]/
│   │       └── route.ts
│   └── health/
│       └── route.ts
├── lib/
│   ├── supabase/
│   │   ├── client.ts
│   │   ├── server.ts
│   │   └── middleware.ts
│   ├── replicate.ts
│   ├── logging.ts
│   └── validation.ts
└── middleware.ts
```

---

## 2. Supabase Configuration

### 2.1 Supabase Client (Browser)

Create `app/lib/supabase/client.ts`:

```typescript
import { createBrowserClient } from "@supabase/ssr";

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!
  );
}
```

### 2.2 Supabase Client (Server)

Create `app/lib/supabase/server.ts`:

```typescript
import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { cookies } from "next/headers";

export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll();
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            );
          } catch {
            // Called from Server Component
          }
        },
      },
    }
  );
}
```

### 2.3 Supabase Service Role Client

Create `app/lib/supabase/service.ts`:

```typescript
import { createClient } from "@supabase/supabase-js";

export function createServiceClient() {
  return createClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.SUPABASE_SERVICE_ROLE_KEY!,
    {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    }
  );
}
```

---

## 3. Database Schema

### 3.1 Initial Schema Migration

Create `supabase/migrations/001_initial_schema.sql`:

```sql
-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create image_batches table
CREATE TABLE image_batches (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  batch_name TEXT NOT NULL,
  pipeline_mode TEXT NOT NULL CHECK (pipeline_mode IN ('objects', 'clothing')),

  -- Batch stats
  total_images INT NOT NULL,
  completed_count INT DEFAULT 0,
  failed_count INT DEFAULT 0,

  status TEXT DEFAULT 'processing' CHECK (status IN ('processing', 'completed', 'failed', 'cancelled')),

  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  completed_at TIMESTAMP WITH TIME ZONE,

  -- Metadata
  batch_metadata JSONB
);

-- Create image_processing_jobs table
CREATE TABLE image_processing_jobs (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  pipeline_mode TEXT NOT NULL CHECK (pipeline_mode IN ('objects', 'clothing')),

  -- Input references
  input_image_url TEXT NOT NULL,
  secondary_image_url TEXT,

  -- Processing tracking
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  webhook_id TEXT,

  -- Output
  result_image_url TEXT,
  error_message TEXT,

  -- Metadata
  input_storage_path TEXT,
  result_storage_path TEXT,
  batch_id UUID REFERENCES image_batches(id) ON DELETE CASCADE,
  processing_parameters JSONB,

  -- Timestamps
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  started_at TIMESTAMP WITH TIME ZONE,
  completed_at TIMESTAMP WITH TIME ZONE,

  -- Performance
  processing_time_seconds INT,
  replicate_run_id TEXT
);

-- Create processing_models table
CREATE TABLE processing_models (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),

  model_name TEXT NOT NULL UNIQUE,
  pipeline_type TEXT NOT NULL CHECK (pipeline_type IN ('background_removal', 'background_generation', 'virtual_tryon')),

  -- Replicate reference
  replicate_owner TEXT NOT NULL,
  replicate_model_name TEXT NOT NULL,
  replicate_version_id TEXT,

  -- Configuration
  input_schema JSONB,
  cost_per_run DECIMAL(10, 5),
  avg_run_time_seconds INT,

  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create user_model_uploads table (for clothing pipeline)
CREATE TABLE user_model_uploads (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,

  model_image_url TEXT NOT NULL,
  storage_path TEXT NOT NULL,
  model_description TEXT,

  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),

  UNIQUE(user_id, storage_path)
);

-- Create indexes
CREATE INDEX idx_user_batches ON image_batches(user_id, created_at DESC);
CREATE INDEX idx_user_pipeline_jobs ON image_processing_jobs(user_id, pipeline_mode);
CREATE INDEX idx_status_batch_jobs ON image_processing_jobs(status, batch_id);
CREATE INDEX idx_webhook_id ON image_processing_jobs(webhook_id) WHERE webhook_id IS NOT NULL;
CREATE INDEX idx_batch_status ON image_batches(user_id, status);
```

### 3.2 Row Level Security Policies

Create `supabase/migrations/002_rls_policies.sql`:

```sql
-- Enable RLS on all tables
ALTER TABLE image_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE image_processing_jobs ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_model_uploads ENABLE ROW LEVEL SECURITY;

-- image_batches policies
CREATE POLICY "Users can view own batches"
  ON image_batches FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create own batches"
  ON image_batches FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own batches"
  ON image_batches FOR UPDATE
  USING (auth.uid() = user_id);

-- image_processing_jobs policies
CREATE POLICY "Users can view own jobs"
  ON image_processing_jobs FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create own jobs"
  ON image_processing_jobs FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own jobs"
  ON image_processing_jobs FOR UPDATE
  USING (auth.uid() = user_id);

-- user_model_uploads policies
CREATE POLICY "Users can view own models"
  ON user_model_uploads FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "Users can create own models"
  ON user_model_uploads FOR INSERT
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update own models"
  ON user_model_uploads FOR UPDATE
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete own models"
  ON user_model_uploads FOR DELETE
  USING (auth.uid() = user_id);
```

### 3.3 Seed Data (Development)

Create `supabase/seed.sql`:

```sql
-- Insert default processing models
INSERT INTO processing_models (model_name, pipeline_type, replicate_owner, replicate_model_name, cost_per_run, avg_run_time_seconds) VALUES
('background_removal', 'background_removal', 'cjwbw', 'rembg', 0.001, 3),
('stable_diffusion_inpaint', 'background_generation', 'stability-ai', 'stable-diffusion-inpainting', 0.05, 15),
('virtual_tryon', 'virtual_tryon', 'fofr', 'try-on', 0.10, 25);
```

---

## 4. Storage Structure

### 4.1 Create Storage Buckets

Via Supabase Dashboard or SQL:

```sql
-- Create storage buckets
INSERT INTO storage.buckets (id, name, public) VALUES
('uploads', 'uploads', false),
('results', 'results', true),
('models', 'models', false);
```

### 4.2 Storage Policies

```sql
-- uploads bucket policies (private)
CREATE POLICY "Users can upload own files"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'uploads' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Users can view own files"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'uploads' AND auth.uid()::text = (storage.foldername(name))[1]);

-- results bucket policies (public read)
CREATE POLICY "Anyone can view results"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'results');

CREATE POLICY "Service role can upload results"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'results');

-- models bucket policies
CREATE POLICY "Users can upload own models"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'models' AND auth.uid()::text = (storage.foldername(name))[1]);

CREATE POLICY "Users can view own models"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'models' AND auth.uid()::text = (storage.foldername(name))[1]);
```

### 4.3 Storage Helper Functions

Create `app/lib/storage.ts`:

```typescript
import { createServiceClient } from "./supabase/service";

export async function uploadToStorage(
  bucket: string,
  path: string,
  file: File | Buffer,
  contentType?: string
): Promise<{ url: string; path: string } | null> {
  const supabase = createServiceClient();

  const { data, error } = await supabase.storage
    .from(bucket)
    .upload(path, file, {
      contentType: contentType || "image/jpeg",
      upsert: false,
    });

  if (error) {
    console.error("Storage upload error:", error);
    return null;
  }

  const { data: urlData } = supabase.storage
    .from(bucket)
    .getPublicUrl(data.path);

  return {
    url: urlData.publicUrl,
    path: data.path,
  };
}

export async function getSignedUrl(
  bucket: string,
  path: string,
  expiresIn: number = 3600
): Promise<string | null> {
  const supabase = createServiceClient();

  const { data, error } = await supabase.storage
    .from(bucket)
    .createSignedUrl(path, expiresIn);

  if (error) {
    console.error("Signed URL error:", error);
    return null;
  }

  return data.signedUrl;
}

export async function downloadFromUrl(url: string): Promise<Buffer | null> {
  try {
    const response = await fetch(url);
    if (!response.ok) throw new Error("Download failed");

    const arrayBuffer = await response.arrayBuffer();
    return Buffer.from(arrayBuffer);
  } catch (error) {
    console.error("Download error:", error);
    return null;
  }
}
```

---

## 5. Authentication Middleware

### 5.1 Root Middleware

Create `middleware.ts`:

```typescript
import { createServerClient, type CookieOptions } from "@supabase/ssr";
import { NextResponse, type NextRequest } from "next/server";

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
            request.cookies.set(name, value)
          );
          response = NextResponse.next({
            request,
          });
          cookiesToSet.forEach(({ name, value, options }) =>
            response.cookies.set(name, value, options)
          );
        },
      },
    }
  );

  const {
    data: { user },
  } = await supabase.auth.getUser();

  // Protect API routes (except webhook and health)
  if (request.nextUrl.pathname.startsWith("/api")) {
    const isWebhook = request.nextUrl.pathname.startsWith("/api/webhook");
    const isHealth = request.nextUrl.pathname === "/api/health";

    if (!isWebhook && !isHealth && !user) {
      return NextResponse.json(
        { error: "Unauthorized" },
        { status: 401 }
      );
    }
  }

  // Protect app routes
  if (request.nextUrl.pathname.startsWith("/app") && !user) {
    return NextResponse.redirect(new URL("/auth/login", request.url));
  }

  return response;
}

export const config = {
  matcher: [
    "/app/:path*",
    "/api/:path*",
    "/((?!_next/static|_next/image|favicon.ico|.*\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
```

### 5.2 Auth Helper Functions

Create `app/lib/auth.ts`:

```typescript
import { createClient } from "./supabase/server";
import { createServiceClient } from "./supabase/service";
import { NextRequest } from "next/server";

export async function getCurrentUser() {
  const supabase = await createClient();
  const {
    data: { user },
    error,
  } = await supabase.auth.getUser();

  if (error || !user) {
    return null;
  }

  return user;
}

export async function getUserFromRequest(request: NextRequest) {
  const authHeader = request.headers.get("authorization");

  if (!authHeader || !authHeader.startsWith("Bearer ")) {
    return null;
  }

  const token = authHeader.substring(7);
  const supabase = createServiceClient();

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser(token);

  if (error || !user) {
    return null;
  }

  return user;
}

export async function requireAuth(request: NextRequest) {
  const user = await getUserFromRequest(request);

  if (!user) {
    throw new Error("Unauthorized");
  }

  return user;
}
```

---

## 6. Replicate API Integration

### 6.1 Replicate Client Setup

Create `app/lib/replicate.ts`:

```typescript
import Replicate from "replicate";

export const replicate = new Replicate({
  auth: process.env.REPLICATE_API_TOKEN!,
});

export type PipelineMode = "objects" | "clothing";

export interface ReplicateModel {
  owner: string;
  name: string;
  version?: string;
}

// Model configurations
export const MODELS = {
  background_removal: {
    owner: "cjwbw",
    name: "rembg",
  },
  background_generation: {
    owner: "stability-ai",
    name: "stable-diffusion-inpainting",
  },
  virtual_tryon: {
    owner: "fofr",
    name: "try-on",
  },
};

export async function createPrediction(
  model: ReplicateModel,
  input: Record<string, any>,
  webhookUrl: string
) {
  const modelString = model.version
    ? `${model.owner}/${model.name}:${model.version}`
    : `${model.owner}/${model.name}`;

  const prediction = await replicate.predictions.create({
    model: modelString,
    input,
    webhook: webhookUrl,
    webhook_events_filter: ["completed"],
  });

  return prediction;
}

export async function getPrediction(predictionId: string) {
  return await replicate.predictions.get(predictionId);
}
```

### 6.2 Pipeline-Specific Functions

```typescript
// Add to replicate.ts

export async function processObjectsBackgroundRemoval(
  imageUrl: string,
  webhookUrl: string
) {
  return await createPrediction(
    MODELS.background_removal,
    {
      image: imageUrl,
    },
    webhookUrl
  );
}

export async function processObjectsBackgroundGeneration(
  imageUrl: string,
  backgroundPrompt: string,
  webhookUrl: string
) {
  return await createPrediction(
    MODELS.background_generation,
    {
      image: imageUrl,
      prompt: backgroundPrompt,
      num_outputs: 1,
    },
    webhookUrl
  );
}

export async function processClothingVirtualTryon(
  garmentUrl: string,
  modelUrl: string,
  webhookUrl: string
) {
  return await createPrediction(
    MODELS.virtual_tryon,
    {
      garm_img: garmentUrl,
      human_img: modelUrl,
      garment_des: "clothing item",
    },
    webhookUrl
  );
}
```

---

## 7. API Endpoint: Upload

Create `app/api/upload/route.ts`:

```typescript
import { NextRequest, NextResponse } from "next/server";
import { requireAuth } from "@/app/lib/auth";
import { createServiceClient } from "@/app/lib/supabase/service";
import { v4 as uuidv4 } from "uuid";

const MAX_FILE_SIZE = 10 * 1024 * 1024; // 10MB
const MAX_FILES = 10;
const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp"];

export async function POST(request: NextRequest) {
  try {
    // Authenticate user
    const user = await requireAuth(request);
    const supabase = createServiceClient();

    // Parse form data
    const formData = await request.formData();
    const files = formData.getAll("files") as File[];
    const pipeline_mode = formData.get("pipeline_mode") as string;
    const batch_name = (formData.get("batch_name") as string) || 
      `Batch ${new Date().toLocaleDateString()}`;
    const secondary_file = formData.get("secondary_file") as File | null;

    // Validation
    if (!files || files.length === 0) {
      return NextResponse.json(
        { error: "No files provided" },
        { status: 400 }
      );
    }

    if (!pipeline_mode || !["objects", "clothing"].includes(pipeline_mode)) {
      return NextResponse.json(
        { error: "Invalid pipeline_mode" },
        { status: 400 }
      );
    }

    if (files.length > MAX_FILES) {
      return NextResponse.json(
        { error: `Maximum ${MAX_FILES} files allowed` },
        { status: 400 }
      );
    }

    // Validate file sizes and types
    for (const file of files) {
      if (file.size > MAX_FILE_SIZE) {
        return NextResponse.json(
          { error: `File ${file.name} exceeds 10MB limit` },
          { status: 400 }
        );
      }

      if (!ALLOWED_TYPES.includes(file.type)) {
        return NextResponse.json(
          { error: `File ${file.name} has invalid type. Allowed: JPEG, PNG, WebP` },
          { status: 400 }
        );
      }
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
        status: "processing",
      });

    if (batchError) {
      console.error("Batch creation error:", batchError);
      return NextResponse.json(
        { error: "Failed to create batch" },
        { status: 500 }
      );
    }

    // Handle secondary file (for clothing pipeline)
    let secondaryImageUrl: string | null = null;
    if (pipeline_mode === "clothing" && secondary_file) {
      const secondaryPath = `models/${user.id}/${uuidv4()}_${secondary_file.name}`;
      const { error: secondaryUploadError } = await supabase.storage
        .from("models")
        .upload(secondaryPath, secondary_file, { upsert: false });

      if (!secondaryUploadError) {
        const { data: urlData } = supabase.storage
          .from("models")
          .getPublicUrl(secondaryPath);
        secondaryImageUrl = urlData.publicUrl;
      }
    }

    // Upload files and create job records
    const uploadPromises = files.map(async (file) => {
      const file_id = uuidv4();
      const storage_path = `uploads/${user.id}/raw/${batch_id}/${file_id}_${file.name}`;

      try {
        // Upload to Supabase Storage
        const { error: uploadError } = await supabase.storage
          .from("uploads")
          .upload(storage_path, file, { upsert: false });

        if (uploadError) {
          console.error("Storage upload error:", uploadError);
          return { success: false, error: uploadError.message };
        }

        // Get public URL
        const { data: urlData } = supabase.storage
          .from("uploads")
          .getPublicUrl(storage_path);

        // Create job record
        const { error: jobError } = await supabase
          .from("image_processing_jobs")
          .insert({
            id: file_id,
            user_id: user.id,
            batch_id,
            pipeline_mode,
            input_storage_path: storage_path,
            input_image_url: urlData.publicUrl,
            secondary_image_url: secondaryImageUrl,
            status: "pending",
          });

        if (jobError) {
          console.error("Job creation error:", jobError);
          return { success: false, error: jobError.message };
        }

        return { success: true, job_id: file_id };
      } catch (error) {
        console.error("Upload process error:", error);
        return { success: false, error: String(error) };
      }
    });

    const results = await Promise.all(uploadPromises);
    const successCount = results.filter((r) => r.success).length;
    const failureCount = results.filter((r) => !r.success).length;

    // Update batch if some uploads failed
    if (failureCount > 0) {
      await supabase
        .from("image_batches")
        .update({
          total_images: successCount,
          failed_count: failureCount,
        })
        .eq("id", batch_id);
    }

    return NextResponse.json(
      {
        batch_id,
        total_images: successCount,
        failed_uploads: failureCount,
        uploaded_at: new Date().toISOString(),
        message: "Images uploaded successfully",
      },
      { status: 201 }
    );
  } catch (error) {
    console.error("Upload endpoint error:", error);

    if (error instanceof Error && error.message === "Unauthorized") {
      return NextResponse.json(
        { error: "Unauthorized" },
        { status: 401 }
      );
    }

    return NextResponse.json(
      { error: "Upload failed" },
      { status: 500 }
    );
  }
}
```

---

## 8. API Endpoint: Process Batch

Create `app/api/process-batch/route.ts`:

```typescript
import { NextRequest, NextResponse } from "next/server";
import { requireAuth } from "@/app/lib/auth";
import { createServiceClient } from "@/app/lib/supabase/service";
import {
  processObjectsBackgroundRemoval,
  processClothingVirtualTryon,
} from "@/app/lib/replicate";

export async function POST(request: NextRequest) {
  try {
    const user = await requireAuth(request);
    const supabase = createServiceClient();

    const body = await request.json();
    const { batch_id, processing_params } = body;

    if (!batch_id) {
      return NextResponse.json(
        { error: "batch_id is required" },
        { status: 400 }
      );
    }

    // Verify batch belongs to user
    const { data: batch, error: batchError } = await supabase
      .from("image_batches")
      .select("*")
      .eq("id", batch_id)
      .eq("user_id", user.id)
      .single();

    if (batchError || !batch) {
      return NextResponse.json(
        { error: "Batch not found" },
        { status: 404 }
      );
    }

    // Get all pending jobs for this batch
    const { data: jobs, error: fetchError } = await supabase
      .from("image_processing_jobs")
      .select("*")
      .eq("batch_id", batch_id)
      .eq("status", "pending");

    if (fetchError) {
      return NextResponse.json(
        { error: "Failed to fetch jobs" },
        { status: 500 }
      );
    }

    if (!jobs || jobs.length === 0) {
      return NextResponse.json(
        { error: "No pending jobs found" },
        { status: 400 }
      );
    }

    const webhookUrl = `${process.env.NEXT_PUBLIC_API_URL}/api/webhook/replicate`;
    const processedJobs: string[] = [];

    // Process each job
    for (const job of jobs) {
      try {
        let prediction;

        if (batch.pipeline_mode === "objects") {
          // Pipeline A: Background removal (Step 1)
          prediction = await processObjectsBackgroundRemoval(
            job.input_image_url,
            webhookUrl
          );

          await supabase
            .from("image_processing_jobs")
            .update({
              webhook_id: prediction.id,
              replicate_run_id: prediction.id,
              status: "processing",
              started_at: new Date().toISOString(),
              processing_parameters: {
                step: 1,
                background_prompt: processing_params?.background_prompt || "studio lighting on marble table",
              },
            })
            .eq("id", job.id);
        } else if (batch.pipeline_mode === "clothing") {
          // Pipeline B: Virtual try-on
          if (!job.secondary_image_url) {
            throw new Error("Model image required for clothing pipeline");
          }

          prediction = await processClothingVirtualTryon(
            job.input_image_url,
            job.secondary_image_url,
            webhookUrl
          );

          await supabase
            .from("image_processing_jobs")
            .update({
              webhook_id: prediction.id,
              replicate_run_id: prediction.id,
              status: "processing",
              started_at: new Date().toISOString(),
            })
            .eq("id", job.id);
        }

        processedJobs.push(job.id);
      } catch (error) {
        console.error(`Job ${job.id} processing error:`, error);

        await supabase
          .from("image_processing_jobs")
          .update({
            status: "failed",
            error_message: String(error),
          })
          .eq("id", job.id);

        // Update batch failed count
        await supabase
          .from("image_batches")
          .update({
            failed_count: batch.failed_count + 1,
          })
          .eq("id", batch_id);
      }
    }

    return NextResponse.json(
      {
        batch_id,
        jobs_started: processedJobs.length,
        total_jobs: jobs.length,
        webhook_url: webhookUrl,
        message: "Batch processing started",
      },
      { status: 202 }
    );
  } catch (error) {
    console.error("Process batch error:", error);

    if (error instanceof Error && error.message === "Unauthorized") {
      return NextResponse.json(
        { error: "Unauthorized" },
        { status: 401 }
      );
    }

    return NextResponse.json(
      { error: "Processing failed" },
      { status: 500 }
    );
  }
}
```

---

## 9. API Endpoint: Webhook Handler

Create `app/api/webhook/replicate/route.ts`:

```typescript
import { NextRequest, NextResponse } from "next/server";
import { createServiceClient } from "@/app/lib/supabase/service";
import { downloadFromUrl, uploadToStorage } from "@/app/lib/storage";
import crypto from "crypto";

export async function POST(request: NextRequest) {
  try {
    // Validate webhook signature
    const signature = request.headers.get("x-replicate-webhook-secret");
    const body = await request.text();

    if (process.env.REPLICATE_WEBHOOK_SECRET) {
      const expectedSignature = crypto
        .createHmac("sha256", process.env.REPLICATE_WEBHOOK_SECRET)
        .update(body)
        .digest("hex");

      if (signature !== expectedSignature) {
        console.warn("Invalid webhook signature");
        return NextResponse.json(
          { error: "Invalid signature" },
          { status: 401 }
        );
      }
    }

    const payload = JSON.parse(body);
    const { id, status, output, error: replicateError } = payload;

    const supabase = createServiceClient();

    // Find job by webhook_id
    const { data: job, error: fetchError } = await supabase
      .from("image_processing_jobs")
      .select("*")
      .eq("webhook_id", id)
      .single();

    if (fetchError || !job) {
      console.error("Job not found for webhook:", id);
      return NextResponse.json(
        { error: "Job not found" },
        { status: 404 }
      );
    }

    if (status === "succeeded" && output) {
      // Extract result URL
      const resultUrl = Array.isArray(output) ? output[0] : output;

      // Download result from Replicate
      const imageBuffer = await downloadFromUrl(resultUrl);

      if (!imageBuffer) {
        throw new Error("Failed to download result image");
      }

      // Upload to Supabase Storage
      const timestamp = Date.now();
      const resultPath = `results/${job.user_id}/processed/${job.batch_id}/${timestamp}.jpg`;

      const uploadResult = await uploadToStorage(
        "results",
        resultPath,
        imageBuffer,
        "image/jpeg"
      );

      if (!uploadResult) {
        throw new Error("Failed to upload result to storage");
      }

      // Calculate processing time
      const completedAt = new Date();
      const startedAt = new Date(job.started_at);
      const processingTime = Math.round(
        (completedAt.getTime() - startedAt.getTime()) / 1000
      );

      // Check if this is step 1 of Objects pipeline (background removal)
      const params = job.processing_parameters as any;
      if (job.pipeline_mode === "objects" && params?.step === 1) {
        // This is step 1 (background removal), need to trigger step 2
        // For now, just mark as completed. In production, trigger step 2 here.
        await supabase
          .from("image_processing_jobs")
          .update({
            status: "completed",
            result_image_url: uploadResult.url,
            result_storage_path: uploadResult.path,
            completed_at: completedAt.toISOString(),
            processing_time_seconds: processingTime,
          })
          .eq("id", job.id);
      } else {
        // Final step - mark as completed
        await supabase
          .from("image_processing_jobs")
          .update({
            status: "completed",
            result_image_url: uploadResult.url,
            result_storage_path: uploadResult.path,
            completed_at: completedAt.toISOString(),
            processing_time_seconds: processingTime,
          })
          .eq("id", job.id);
      }

      // Update batch stats
      const { data: batch } = await supabase
        .from("image_batches")
        .select("completed_count, total_images")
        .eq("id", job.batch_id)
        .single();

      if (batch) {
        const newCompletedCount = (batch.completed_count || 0) + 1;
        const isComplete = newCompletedCount === batch.total_images;

        await supabase
          .from("image_batches")
          .update({
            completed_count: newCompletedCount,
            status: isComplete ? "completed" : "processing",
            completed_at: isComplete ? new Date().toISOString() : null,
          })
          .eq("id", job.batch_id);
      }

      return NextResponse.json(
        {
          processed: true,
          job_id: job.id,
          result_stored: true,
        },
        { status: 200 }
      );
    } else if (status === "failed" || replicateError) {
      // Mark job as failed
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

      if (batch) {
        await supabase
          .from("image_batches")
          .update({
            failed_count: (batch.failed_count || 0) + 1,
          })
          .eq("id", job.batch_id);
      }

      return NextResponse.json(
        {
          processed: true,
          job_id: job.id,
          status: "failed",
        },
        { status: 200 }
      );
    }

    return NextResponse.json(
      { message: "Webhook received" },
      { status: 200 }
    );
  } catch (error) {
    console.error("Webhook processing error:", error);
    return NextResponse.json(
      { error: "Webhook processing failed" },
      { status: 500 }
    );
  }
}
```

---

## 10. API Endpoint: Batch Status

Create `app/api/batches/[id]/route.ts`:

```typescript
import { NextRequest, NextResponse } from "next/server";
import { requireAuth } from "@/app/lib/auth";
import { createServiceClient } from "@/app/lib/supabase/service";

export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const user = await requireAuth(request);
    const supabase = createServiceClient();
    const batch_id = params.id;

    // Fetch batch info
    const { data: batch, error: batchError } = await supabase
      .from("image_batches")
      .select("*")
      .eq("id", batch_id)
      .eq("user_id", user.id)
      .single();

    if (batchError || !batch) {
      return NextResponse.json(
        { error: "Batch not found" },
        { status: 404 }
      );
    }

    // Fetch all jobs for this batch
    const { data: jobs, error: jobsError } = await supabase
      .from("image_processing_jobs")
      .select("*")
      .eq("batch_id", batch_id)
      .order("created_at", { ascending: true });

    if (jobsError) {
      return NextResponse.json(
        { error: "Failed to fetch jobs" },
        { status: 500 }
      );
    }

    // Calculate stats
    const processingCount = jobs?.filter((j) => j.status === "processing").length || 0;
    const pendingCount = jobs?.filter((j) => j.status === "pending").length || 0;

    return NextResponse.json(
      {
        batch_id: batch.id,
        batch_name: batch.batch_name,
        pipeline_mode: batch.pipeline_mode,
        total_images: batch.total_images,
        completed: batch.completed_count,
        processing: processingCount,
        pending: pendingCount,
        failed: batch.failed_count,
        status: batch.status,
        created_at: batch.created_at,
        completed_at: batch.completed_at,
        jobs: jobs || [],
      },
      { status: 200 }
    );
  } catch (error) {
    console.error("Batch status error:", error);

    if (error instanceof Error && error.message === "Unauthorized") {
      return NextResponse.json(
        { error: "Unauthorized" },
        { status: 401 }
      );
    }

    return NextResponse.json(
      { error: "Failed to fetch batch status" },
      { status: 500 }
    );
  }
}
```

---

## 11. Error Handling

Create `app/lib/errors.ts`:

```typescript
export class AppError extends Error {
  constructor(
    message: string,
    public statusCode: number = 500,
    public code?: string
  ) {
    super(message);
    this.name = "AppError";
  }
}

export class ValidationError extends AppError {
  constructor(message: string) {
    super(message, 400, "VALIDATION_ERROR");
    this.name = "ValidationError";
  }
}

export class AuthenticationError extends AppError {
  constructor(message: string = "Unauthorized") {
    super(message, 401, "AUTHENTICATION_ERROR");
    this.name = "AuthenticationError";
  }
}

export class NotFoundError extends AppError {
  constructor(message: string = "Resource not found") {
    super(message, 404, "NOT_FOUND");
    this.name = "NotFoundError";
  }
}

export function handleApiError(error: unknown) {
  console.error("API Error:", error);

  if (error instanceof AppError) {
    return {
      error: error.message,
      code: error.code,
      statusCode: error.statusCode,
    };
  }

  if (error instanceof Error) {
    return {
      error: error.message,
      statusCode: 500,
    };
  }

  return {
    error: "An unexpected error occurred",
    statusCode: 500,
  };
}
```

---

## 12. Logging & Monitoring

Create `app/lib/logging.ts`:

```typescript
type LogLevel = "info" | "warn" | "error" | "debug";

interface LogEntry {
  timestamp: string;
  level: LogLevel;
  event: string;
  data?: Record<string, any>;
  userId?: string;
}

export async function logEvent(
  event: string,
  data?: Record<string, any>,
  level: LogLevel = "info",
  userId?: string
) {
  const logEntry: LogEntry = {
    timestamp: new Date().toISOString(),
    level,
    event,
    data,
    userId,
  };

  // Console logging (always)
  const logMethod = level === "error" ? console.error : 
                    level === "warn" ? console.warn : 
                    console.log;

  logMethod(`[${level.toUpperCase()}] ${event}`, data || "");

  // Production: Send to external service (Sentry, LogRocket, etc.)
  if (process.env.NODE_ENV === "production" && process.env.SENTRY_DSN) {
    // Example: Sentry integration
    // Sentry.captureMessage(event, { level, extra: data });
  }

  // Optional: Store in database for analytics
  // const supabase = createServiceClient();
  // await supabase.from("activity_logs").insert(logEntry);
}

export async function logError(
  error: Error,
  context?: Record<string, any>,
  userId?: string
) {
  await logEvent(
    "error_occurred",
    {
      error: error.message,
      stack: error.stack,
      ...context,
    },
    "error",
    userId
  );
}
```

Create health check endpoint `app/api/health/route.ts`:

```typescript
import { NextResponse } from "next/server";
import { createServiceClient } from "@/app/lib/supabase/service";

export async function GET() {
  const checks = {
    status: "healthy",
    timestamp: new Date().toISOString(),
    services: {
      supabase: false,
      replicate: false,
    },
  };

  try {
    // Test Supabase connection
    const supabase = createServiceClient();
    const { error } = await supabase.from("image_batches").select("id").limit(1);
    checks.services.supabase = !error;
  } catch {
    checks.services.supabase = false;
  }

  try {
    // Test Replicate API
    const response = await fetch("https://api.replicate.com/v1/models", {
      headers: {
        Authorization: `Token ${process.env.REPLICATE_API_TOKEN}`,
      },
    });
    checks.services.replicate = response.ok;
  } catch {
    checks.services.replicate = false;
  }

  const allHealthy = Object.values(checks.services).every(Boolean);
  checks.status = allHealthy ? "healthy" : "degraded";

  return NextResponse.json(checks, {
    status: allHealthy ? 200 : 503,
  });
}
```

---

## 13. Testing

Create `__tests__/api/upload.test.ts`:

```typescript
import { describe, it, expect, jest } from "@jest/globals";

describe("Upload API", () => {
  it("should require authentication", async () => {
    const response = await fetch("http://localhost:3000/api/upload", {
      method: "POST",
    });

    expect(response.status).toBe(401);
  });

  it("should validate file types", async () => {
    // Mock authenticated request with invalid file type
    // Implementation depends on test setup
  });

  it("should create batch and jobs", async () => {
    // Test successful upload flow
  });
});
```

---

## 14. Deployment

### 14.1 Vercel Deployment

```bash
# Install Vercel CLI
npm i -g vercel

# Login
vercel login

# Link project
vercel link

# Set environment variables
vercel env add NEXT_PUBLIC_SUPABASE_URL production
vercel env add SUPABASE_SERVICE_ROLE_KEY production
vercel env add REPLICATE_API_TOKEN production
vercel env add REPLICATE_WEBHOOK_SECRET production

# Deploy
vercel --prod
```

### 14.2 Environment Configuration

Ensure all environment variables are set in Vercel dashboard.

---

## 15. Performance Optimization

### 15.1 Connection Pooling

Use Supabase connection pooling for high-traffic scenarios.

### 15.2 Caching

Implement caching for batch status queries:

```typescript
// Example: Cache batch status for 10 seconds
const cache = new Map<string, { data: any; timestamp: number }>();

export function getCachedBatchStatus(batchId: string) {
  const cached = cache.get(batchId);
  if (cached && Date.now() - cached.timestamp < 10000) {
    return cached.data;
  }
  return null;
}
```

### 15.3 Batch Processing Optimization

Process webhooks in batches to reduce database queries.

---

## Document Maintenance

**Last Updated:** February 12, 2026  
**Version:** 1.0  
**Maintainer:** Backend Team  

**Related Documents:**
- [EXECUTION_PLAN.md](./EXECUTION_PLAN.md)
- [FE_EXECUTION.md](./FE_EXECUTION.md)
