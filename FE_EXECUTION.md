# FE_EXECUTION.md
## Frontend Implementation Guide - AI Product Photography Augmentation

> **Note for AI Assistants:** This document is designed to be modified by AI agents. Update components, add new UI patterns, refactor implementations, or expand on design patterns as needed. Maintain React best practices and accessibility standards.

---

## Document Overview

This is the **detailed frontend implementation guide** for the AI Product Photography Augmentation project. This document covers:
- Next.js 16 App Router & React Components
- Supabase Real-time Subscriptions
- UI/UX Design Patterns
- State Management
- Form Handling & Validation
- Responsive Design
- Performance Optimization

**Related Documents:**
- [EXECUTION_PLAN.md](./EXECUTION_PLAN.md) - Master project overview
- [BE_EXECUTION.md](./BE_EXECUTION.md) - Backend implementation guide

---

## Table of Contents

1. [Tech Stack & Setup](#1-tech-stack--setup)
2. [Authentication UI](#2-authentication-ui)
3. [Upload Component](#3-upload-component)
4. [Batch Monitor Component](#4-batch-monitor-component)
5. [Real-time Updates](#5-real-time-updates)
6. [Results Gallery](#6-results-gallery)
7. [User Dashboard](#7-user-dashboard)
8. [Responsive Design](#8-responsive-design)
9. [Component Testing](#9-component-testing)
10. [Performance Optimization](#10-performance-optimization)
11. [Accessibility](#11-accessibility)
12. [UI Component Library](#12-ui-component-library)

---

## 1. Tech Stack & Setup

### 1.1 Dependencies

```bash
# Core
npm install react react-dom next

# Supabase
npm install @supabase/supabase-js @supabase/ssr

# UI Libraries
npm install clsx tailwind-merge lucide-react

# Form handling
npm install react-hook-form zod @hookform/resolvers

# File upload
npm install react-dropzone

# Utilities
npm install date-fns

# Development
npm install -D @types/react @types/node tailwindcss postcss autoprefixer
npm install -D @testing-library/react @testing-library/jest-dom @testing-library/user-event
```

### 1.2 Tailwind Configuration

Update `tailwind.config.ts`:

```typescript
import type { Config } from "tailwindcss";

const config: Config = {
  content: [
    "./pages/**/*.{js,ts,jsx,tsx,mdx}",
    "./components/**/*.{js,ts,jsx,tsx,mdx}",
    "./app/**/*.{js,ts,jsx,tsx,mdx}",
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: "#eff6ff",
          100: "#dbeafe",
          200: "#bfdbfe",
          300: "#93c5fd",
          400: "#60a5fa",
          500: "#3b82f6",
          600: "#2563eb",
          700: "#1d4ed8",
          800: "#1e40af",
          900: "#1e3a8a",
        },
      },
      animation: {
        "spin-slow": "spin 3s linear infinite",
        "pulse-fast": "pulse 1s cubic-bezier(0.4, 0, 0.6, 1) infinite",
      },
    },
  },
  plugins: [],
};

export default config;
```

### 1.3 Project Structure

```
app/
├── (auth)/
│   ├── login/
│   │   └── page.tsx
│   ├── signup/
│   │   └── page.tsx
│   └── layout.tsx
├── app/
│   ├── dashboard/
│   │   └── page.tsx
│   ├── upload/
│   │   └── page.tsx
│   └── batch/
│       └── [id]/
│           └── page.tsx
├── components/
│   ├── ui/
│   │   ├── Button.tsx
│   │   ├── Input.tsx
│   │   ├── Card.tsx
│   │   └── Badge.tsx
│   ├── auth/
│   │   ├── LoginForm.tsx
│   │   └── SignupForm.tsx
│   ├── upload/
│   │   ├── UploadForm.tsx
│   │   ├── PipelineSelector.tsx
│   │   └── FileDropzone.tsx
│   ├── batch/
│   │   ├── BatchMonitor.tsx
│   │   ├── JobCard.tsx
│   │   └── ProgressBar.tsx
│   └── dashboard/
│       ├── BatchList.tsx
│       └── StatsCard.tsx
├── hooks/
│   ├── useAuth.ts
│   ├── useBatch.ts
│   └── useRealtime.ts
├── lib/
│   ├── supabase/
│   │   └── client.ts
│   └── utils.ts
├── types/
│   └── index.ts
└── layout.tsx
```

---

## 2. Authentication UI

### 2.1 Auth Hook

Create `app/hooks/useAuth.ts`:

```typescript
"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/app/lib/supabase/client";
import { User } from "@supabase/supabase-js";
import { useRouter } from "next/navigation";

export function useAuth() {
  const [user, setUser] = useState<User | null>(null);
  const [loading, setLoading] = useState(true);
  const router = useRouter();
  const supabase = createClient();

  useEffect(() => {
    // Get initial session
    supabase.auth.getSession().then(({ data: { session } }) => {
      setUser(session?.user ?? null);
      setLoading(false);
    });

    // Listen for auth changes
    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setUser(session?.user ?? null);
    });

    return () => subscription.unsubscribe();
  }, []);

  const signIn = async (email: string, password: string) => {
    const { data, error } = await supabase.auth.signInWithPassword({
      email,
      password,
    });

    if (error) throw error;
    return data;
  };

  const signUp = async (email: string, password: string) => {
    const { data, error } = await supabase.auth.signUp({
      email,
      password,
    });

    if (error) throw error;
    return data;
  };

  const signOut = async () => {
    await supabase.auth.signOut();
    router.push("/auth/login");
  };

  return {
    user,
    loading,
    signIn,
    signUp,
    signOut,
  };
}
```

### 2.2 Login Form

Create `app/components/auth/LoginForm.tsx`:

```typescript
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { useAuth } from "@/app/hooks/useAuth";
import { Button } from "@/app/components/ui/Button";
import { Input } from "@/app/components/ui/Input";

export function LoginForm() {
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);
  const { signIn } = useAuth();
  const router = useRouter();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);

    try {
      await signIn(email, password);
      router.push("/app/dashboard");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Login failed");
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-4 w-full max-w-md">
      <div>
        <label htmlFor="email" className="block text-sm font-medium mb-2">
          Email
        </label>
        <Input
          id="email"
          type="email"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          placeholder="you@example.com"
          required
          disabled={loading}
        />
      </div>

      <div>
        <label htmlFor="password" className="block text-sm font-medium mb-2">
          Password
        </label>
        <Input
          id="password"
          type="password"
          value={password}
          onChange={(e) => setPassword(e.target.value)}
          placeholder="••••••••"
          required
          disabled={loading}
        />
      </div>

      {error && (
        <div className="bg-red-50 text-red-700 p-3 rounded-md text-sm">
          {error}
        </div>
      )}

      <Button type="submit" disabled={loading} className="w-full">
        {loading ? "Signing in..." : "Sign In"}
      </Button>

      <p className="text-center text-sm text-gray-600">
        Don't have an account?{" "}
        <a href="/auth/signup" className="text-blue-600 hover:underline">
          Sign up
        </a>
      </p>
    </form>
  );
}
```

### 2.3 Login Page

Create `app/(auth)/login/page.tsx`:

```typescript
import { LoginForm } from "@/app/components/auth/LoginForm";

export default function LoginPage() {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="w-full max-w-md">
        <div className="text-center mb-8">
          <h1 className="text-3xl font-bold text-gray-900 mb-2">
            Welcome Back
          </h1>
          <p className="text-gray-600">
            Sign in to enhance your product photos with AI
          </p>
        </div>
        <div className="bg-white p-8 rounded-lg shadow-md">
          <LoginForm />
        </div>
      </div>
    </div>
  );
}
```

---

## 3. Upload Component

### 3.1 Types

Create `app/types/index.ts`:

```typescript
export type PipelineMode = "objects" | "clothing";

export interface UploadFormData {
  files: File[];
  pipelineMode: PipelineMode;
  batchName?: string;
  secondaryFile?: File;
}

export interface Job {
  id: string;
  status: "pending" | "processing" | "completed" | "failed";
  input_image_url: string;
  result_image_url: string | null;
  error_message: string | null;
  processing_time_seconds: number | null;
  completed_at: string | null;
}

export interface Batch {
  id: string;
  batch_name: string;
  pipeline_mode: PipelineMode;
  total_images: number;
  completed_count: number;
  failed_count: number;
  status: "processing" | "completed" | "failed" | "cancelled";
  created_at: string;
  completed_at: string | null;
}
```

### 3.2 Pipeline Selector

Create `app/components/upload/PipelineSelector.tsx`:

```typescript
"use client";

import { PipelineMode } from "@/app/types";
import { Package, Shirt } from "lucide-react";

interface PipelineSelectorProps {
  selected: PipelineMode;
  onSelect: (mode: PipelineMode) => void;
}

export function PipelineSelector({ selected, onSelect }: PipelineSelectorProps) {
  return (
    <div className="grid grid-cols-2 gap-4">
      <button
        type="button"
        onClick={() => onSelect("objects")}
        className={`p-6 rounded-lg border-2 transition-all ${
          selected === "objects"
            ? "border-blue-500 bg-blue-50"
            : "border-gray-200 hover:border-gray-300"
        }`}
      >
        <Package
          className={`w-12 h-12 mx-auto mb-3 ${
            selected === "objects" ? "text-blue-500" : "text-gray-400"
          }`}
        />
        <h3 className="font-semibold text-lg mb-1">Objects</h3>
        <p className="text-sm text-gray-600">
          Professional background replacement for products
        </p>
      </button>

      <button
        type="button"
        onClick={() => onSelect("clothing")}
        className={`p-6 rounded-lg border-2 transition-all ${
          selected === "clothing"
            ? "border-blue-500 bg-blue-50"
            : "border-gray-200 hover:border-gray-300"
        }`}
      >
        <Shirt
          className={`w-12 h-12 mx-auto mb-3 ${
            selected === "clothing" ? "text-blue-500" : "text-gray-400"
          }`}
        />
        <h3 className="font-semibold text-lg mb-1">Clothing</h3>
        <p className="text-sm text-gray-600">
          Virtual try-on for garments on models
        </p>
      </button>
    </div>
  );
}
```

### 3.3 File Dropzone

Create `app/components/upload/FileDropzone.tsx`:

```typescript
"use client";

import { useCallback } from "react";
import { useDropzone } from "react-dropzone";
import { Upload, X } from "lucide-react";

interface FileDropzoneProps {
  files: File[];
  onFilesChange: (files: File[]) => void;
  maxFiles?: number;
}

export function FileDropzone({
  files,
  onFilesChange,
  maxFiles = 10,
}: FileDropzoneProps) {
  const onDrop = useCallback(
    (acceptedFiles: File[]) => {
      const newFiles = [...files, ...acceptedFiles].slice(0, maxFiles);
      onFilesChange(newFiles);
    },
    [files, maxFiles, onFilesChange]
  );

  const { getRootProps, getInputProps, isDragActive } = useDropzone({
    onDrop,
    accept: {
      "image/*": [".jpeg", ".jpg", ".png", ".webp"],
    },
    maxSize: 10 * 1024 * 1024, // 10MB
    maxFiles: maxFiles - files.length,
  });

  const removeFile = (index: number) => {
    const newFiles = files.filter((_, i) => i !== index);
    onFilesChange(newFiles);
  };

  return (
    <div className="space-y-4">
      <div
        {...getRootProps()}
        className={`border-2 border-dashed rounded-lg p-8 text-center cursor-pointer transition-colors ${
          isDragActive
            ? "border-blue-500 bg-blue-50"
            : "border-gray-300 hover:border-gray-400"
        }`}
      >
        <input {...getInputProps()} />
        <Upload className="w-12 h-12 mx-auto mb-4 text-gray-400" />
        {isDragActive ? (
          <p className="text-lg text-blue-600">Drop files here...</p>
        ) : (
          <>
            <p className="text-lg text-gray-700 mb-2">
              Drag & drop images here, or click to select
            </p>
            <p className="text-sm text-gray-500">
              Max {maxFiles} images, 10MB each • JPEG, PNG, WebP
            </p>
          </>
        )}
      </div>

      {files.length > 0 && (
        <div className="space-y-2">
          <p className="text-sm font-medium text-gray-700">
            {files.length} file(s) selected
          </p>
          <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
            {files.map((file, index) => (
              <div
                key={index}
                className="relative group rounded-lg overflow-hidden border border-gray-200"
              >
                <img
                  src={URL.createObjectURL(file)}
                  alt={file.name}
                  className="w-full h-32 object-cover"
                />
                <button
                  type="button"
                  onClick={() => removeFile(index)}
                  className="absolute top-2 right-2 p-1 bg-red-500 text-white rounded-full opacity-0 group-hover:opacity-100 transition-opacity"
                >
                  <X className="w-4 h-4" />
                </button>
                <div className="absolute bottom-0 left-0 right-0 bg-black/50 text-white p-2">
                  <p className="text-xs truncate">{file.name}</p>
                  <p className="text-xs text-gray-300">
                    {(file.size / 1024 / 1024).toFixed(2)} MB
                  </p>
                </div>
              </div>
            ))}
          </div>
        </div>
      )}
    </div>
  );
}
```

### 3.4 Upload Form

Create `app/components/upload/UploadForm.tsx`:

```typescript
"use client";

import { useState } from "react";
import { useRouter } from "next/navigation";
import { createClient } from "@/app/lib/supabase/client";
import { PipelineSelector } from "./PipelineSelector";
import { FileDropzone } from "./FileDropzone";
import { Button } from "@/app/components/ui/Button";
import { Input } from "@/app/components/ui/Input";
import { PipelineMode } from "@/app/types";

export function UploadForm() {
  const [pipelineMode, setPipelineMode] = useState<PipelineMode>("objects");
  const [files, setFiles] = useState<File[]>([]);
  const [batchName, setBatchName] = useState("");
  const [secondaryFile, setSecondaryFile] = useState<File | null>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const router = useRouter();
  const supabase = createClient();

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    setError(null);
    setLoading(true);

    try {
      if (files.length === 0) {
        throw new Error("Please select at least one file");
      }

      // Get auth token
      const {
        data: { session },
      } = await supabase.auth.getSession();

      if (!session) {
        throw new Error("Not authenticated");
      }

      // Prepare form data
      const formData = new FormData();
      files.forEach((file) => formData.append("files", file));
      formData.append("pipeline_mode", pipelineMode);
      formData.append("batch_name", batchName || `Batch ${new Date().toLocaleDateString()}`);

      if (pipelineMode === "clothing" && secondaryFile) {
        formData.append("secondary_file", secondaryFile);
      }

      // Upload
      const response = await fetch("/api/upload", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${session.access_token}`,
        },
        body: formData,
      });

      if (!response.ok) {
        const errorData = await response.json();
        throw new Error(errorData.error || "Upload failed");
      }

      const { batch_id } = await response.json();

      // Redirect to batch page
      router.push(`/app/batch/${batch_id}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Upload failed");
    } finally {
      setLoading(false);
    }
  };

  return (
    <form onSubmit={handleSubmit} className="space-y-8">
      {/* Pipeline Selection */}
      <div>
        <h2 className="text-xl font-semibold mb-4">Select Pipeline</h2>
        <PipelineSelector selected={pipelineMode} onSelect={setPipelineMode} />
      </div>

      {/* Batch Name */}
      <div>
        <label htmlFor="batchName" className="block text-sm font-medium mb-2">
          Batch Name (Optional)
        </label>
        <Input
          id="batchName"
          type="text"
          value={batchName}
          onChange={(e) => setBatchName(e.target.value)}
          placeholder="e.g., Product Photos - February 2026"
          disabled={loading}
        />
      </div>

      {/* File Upload */}
      <div>
        <h2 className="text-xl font-semibold mb-4">Upload Images</h2>
        <FileDropzone files={files} onFilesChange={setFiles} />
      </div>

      {/* Model Photo (Clothing Pipeline) */}
      {pipelineMode === "clothing" && (
        <div>
          <label htmlFor="modelPhoto" className="block text-sm font-medium mb-2">
            Model Photo (Optional)
          </label>
          <input
            id="modelPhoto"
            type="file"
            accept="image/*"
            onChange={(e) => setSecondaryFile(e.target.files?.[0] || null)}
            className="block w-full text-sm text-gray-500 file:mr-4 file:py-2 file:px-4 file:rounded-md file:border-0 file:text-sm file:font-semibold file:bg-blue-50 file:text-blue-700 hover:file:bg-blue-100"
            disabled={loading}
          />
          <p className="text-xs text-gray-500 mt-1">
            Upload a model photo or use default models
          </p>
        </div>
      )}

      {/* Error Message */}
      {error && (
        <div className="bg-red-50 text-red-700 p-4 rounded-md text-sm">
          {error}
        </div>
      )}

      {/* Submit Button */}
      <Button type="submit" disabled={loading || files.length === 0} className="w-full">
        {loading ? "Uploading..." : `Upload ${files.length} Image(s)`}
      </Button>
    </form>
  );
}
```

---

## 4. Batch Monitor Component

### 4.1 Progress Bar

Create `app/components/batch/ProgressBar.tsx`:

```typescript
interface ProgressBarProps {
  current: number;
  total: number;
  label?: string;
}

export function ProgressBar({ current, total, label }: ProgressBarProps) {
  const percentage = total > 0 ? Math.round((current / total) * 100) : 0;

  return (
    <div className="space-y-2">
      {label && (
        <div className="flex justify-between text-sm text-gray-600">
          <span>{label}</span>
          <span>{percentage}%</span>
        </div>
      )}
      <div className="w-full bg-gray-200 rounded-full h-3 overflow-hidden">
        <div
          className="bg-blue-500 h-full rounded-full transition-all duration-300 ease-out"
          style={{ width: `${percentage}%` }}
        />
      </div>
      <p className="text-xs text-gray-500 text-right">
        {current} / {total} completed
      </p>
    </div>
  );
}
```

### 4.2 Job Card

Create `app/components/batch/JobCard.tsx`:

```typescript
import { Job } from "@/app/types";
import { Badge } from "@/app/components/ui/Badge";
import { Download, Loader2, CheckCircle, XCircle } from "lucide-react";
import Image from "next/image";

interface JobCardProps {
  job: Job;
}

export function JobCard({ job }: JobCardProps) {
  const statusConfig = {
    pending: { color: "gray", icon: Loader2, label: "Pending" },
    processing: { color: "blue", icon: Loader2, label: "Processing" },
    completed: { color: "green", icon: CheckCircle, label: "Completed" },
    failed: { color: "red", icon: XCircle, label: "Failed" },
  };

  const config = statusConfig[job.status];
  const Icon = config.icon;

  return (
    <div className="bg-white rounded-lg shadow-md overflow-hidden border border-gray-200">
      {/* Input Image */}
      <div className="relative h-48 bg-gray-100">
        <Image
          src={job.input_image_url}
          alt="Input"
          fill
          className="object-cover"
        />
        <div className="absolute top-2 left-2">
          <Badge color={config.color}>
            <Icon className="w-3 h-3 mr-1 inline" />
            {config.label}
          </Badge>
        </div>
      </div>

      {/* Content */}
      <div className="p-4">
        {/* Processing Time */}
        {job.processing_time_seconds && (
          <p className="text-xs text-gray-500 mb-2">
            Processed in {job.processing_time_seconds}s
          </p>
        )}

        {/* Result or Error */}
        {job.status === "completed" && job.result_image_url ? (
          <div className="space-y-3">
            <div className="relative h-48 bg-gray-100 rounded-md overflow-hidden">
              <Image
                src={job.result_image_url}
                alt="Result"
                fill
                className="object-cover"
              />
            </div>
            <a
              href={job.result_image_url}
              download
              className="block w-full text-center px-4 py-2 bg-blue-500 text-white rounded-md hover:bg-blue-600 transition-colors"
            >
              <Download className="w-4 h-4 inline mr-2" />
              Download
            </a>
          </div>
        ) : job.status === "failed" ? (
          <div className="bg-red-50 p-3 rounded-md text-xs text-red-700">
            {job.error_message || "Processing failed"}
          </div>
        ) : job.status === "processing" ? (
          <div className="flex items-center justify-center py-8">
            <Loader2 className="w-8 h-8 animate-spin text-blue-500" />
          </div>
        ) : null}
      </div>
    </div>
  );
}
```

### 4.3 Batch Monitor

Create `app/components/batch/BatchMonitor.tsx`:

```typescript
"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/app/lib/supabase/client";
import { Batch, Job } from "@/app/types";
import { JobCard } from "./JobCard";
import { ProgressBar } from "./ProgressBar";
import { Button } from "@/app/components/ui/Button";
import { Play, Loader2 } from "lucide-react";

interface BatchMonitorProps {
  batchId: string;
}

export function BatchMonitor({ batchId }: BatchMonitorProps) {
  const [batch, setBatch] = useState<Batch | null>(null);
  const [jobs, setJobs] = useState<Job[]>([]);
  const [loading, setLoading] = useState(true);
  const [processing, setProcessing] = useState(false);
  const supabase = createClient();

  // Initial load
  useEffect(() => {
    loadBatchData();
  }, [batchId]);

  // Real-time subscription
  useEffect(() => {
    const channel = supabase
      .channel(`batch:${batchId}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table: "image_processing_jobs",
          filter: `batch_id=eq.${batchId}`,
        },
        (payload) => {
          if (payload.eventType === "UPDATE") {
            setJobs((prevJobs) =>
              prevJobs.map((job) =>
                job.id === payload.new.id ? (payload.new as Job) : job
              )
            );
          }
        }
      )
      .on(
        "postgres_changes",
        {
          event: "UPDATE",
          schema: "public",
          table: "image_batches",
          filter: `id=eq.${batchId}`,
        },
        (payload) => {
          setBatch(payload.new as Batch);
        }
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [batchId]);

  async function loadBatchData() {
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession();

      if (!session) return;

      const response = await fetch(`/api/batches/${batchId}`, {
        headers: {
          Authorization: `Bearer ${session.access_token}`,
        },
      });

      if (response.ok) {
        const data = await response.json();
        setBatch(data);
        setJobs(data.jobs || []);
      }
    } catch (error) {
      console.error("Failed to load batch:", error);
    } finally {
      setLoading(false);
    }
  }

  async function startProcessing() {
    setProcessing(true);
    try {
      const {
        data: { session },
      } = await supabase.auth.getSession();

      if (!session) return;

      const response = await fetch("/api/process-batch", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${session.access_token}`,
        },
        body: JSON.stringify({
          batch_id: batchId,
          processing_params: {
            background_prompt: "studio lighting on marble table",
          },
        }),
      });

      if (!response.ok) {
        throw new Error("Failed to start processing");
      }

      await loadBatchData();
    } catch (error) {
      console.error("Processing error:", error);
    } finally {
      setProcessing(false);
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center py-12">
        <Loader2 className="w-8 h-8 animate-spin text-blue-500" />
      </div>
    );
  }

  if (!batch) {
    return (
      <div className="text-center py-12">
        <p className="text-gray-600">Batch not found</p>
      </div>
    );
  }

  const hasPendingJobs = jobs.some((job) => job.status === "pending");

  return (
    <div className="space-y-8">
      {/* Batch Header */}
      <div className="bg-white p-6 rounded-lg shadow-md">
        <div className="flex items-center justify-between mb-4">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">{batch.batch_name}</h1>
            <p className="text-sm text-gray-600">
              Pipeline: <span className="font-medium capitalize">{batch.pipeline_mode}</span>
            </p>
          </div>
          {hasPendingJobs && (
            <Button onClick={startProcessing} disabled={processing}>
              {processing ? (
                <>
                  <Loader2 className="w-4 h-4 mr-2 animate-spin" />
                  Starting...
                </>
              ) : (
                <>
                  <Play className="w-4 h-4 mr-2" />
                  Start Processing
                </>
              )}
            </Button>
          )}
        </div>

        {/* Progress */}
        <ProgressBar
          current={batch.completed_count}
          total={batch.total_images}
          label="Overall Progress"
        />

        {/* Stats */}
        <div className="grid grid-cols-4 gap-4 mt-6">
          <div className="text-center">
            <p className="text-2xl font-bold text-gray-900">{batch.total_images}</p>
            <p className="text-sm text-gray-600">Total</p>
          </div>
          <div className="text-center">
            <p className="text-2xl font-bold text-green-600">{batch.completed_count}</p>
            <p className="text-sm text-gray-600">Completed</p>
          </div>
          <div className="text-center">
            <p className="text-2xl font-bold text-blue-600">
              {jobs.filter((j) => j.status === "processing").length}
            </p>
            <p className="text-sm text-gray-600">Processing</p>
          </div>
          <div className="text-center">
            <p className="text-2xl font-bold text-red-600">{batch.failed_count}</p>
            <p className="text-sm text-gray-600">Failed</p>
          </div>
        </div>
      </div>

      {/* Job Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
        {jobs.map((job) => (
          <JobCard key={job.id} job={job} />
        ))}
      </div>
    </div>
  );
}
```

---

## 5. Real-time Updates

### 5.1 Real-time Hook

Create `app/hooks/useRealtime.ts`:

```typescript
"use client";

import { useEffect } from "react";
import { createClient } from "@/app/lib/supabase/client";
import { RealtimePostgresChangesPayload } from "@supabase/supabase-js";

export function useRealtime<T>(
  table: string,
  filter: string,
  onUpdate: (payload: RealtimePostgresChangesPayload<T>) => void
) {
  const supabase = createClient();

  useEffect(() => {
    const channel = supabase
      .channel(`realtime:${table}:${filter}`)
      .on(
        "postgres_changes",
        {
          event: "*",
          schema: "public",
          table,
          filter,
        },
        onUpdate
      )
      .subscribe();

    return () => {
      supabase.removeChannel(channel);
    };
  }, [table, filter]);
}
```

---

## 6. Results Gallery

Create `app/components/batch/ResultsGallery.tsx`:

```typescript
"use client";

import { useState } from "react";
import { Job } from "@/app/types";
import Image from "next/image";
import { Download, X } from "lucide-react";

interface ResultsGalleryProps {
  jobs: Job[];
}

export function ResultsGallery({ jobs }: ResultsGalleryProps) {
  const [selectedJob, setSelectedJob] = useState<Job | null>(null);

  const completedJobs = jobs.filter(
    (job) => job.status === "completed" && job.result_image_url
  );

  if (completedJobs.length === 0) {
    return (
      <div className="text-center py-12 text-gray-500">
        No completed results yet
      </div>
    );
  }

  return (
    <>
      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-4 gap-4">
        {completedJobs.map((job) => (
          <div
            key={job.id}
            className="relative group cursor-pointer rounded-lg overflow-hidden border border-gray-200 hover:shadow-lg transition-shadow"
            onClick={() => setSelectedJob(job)}
          >
            <div className="aspect-square relative">
              <Image
                src={job.result_image_url!}
                alt="Result"
                fill
                className="object-cover"
              />
            </div>
            <div className="absolute inset-0 bg-black/0 group-hover:bg-black/30 transition-colors flex items-center justify-center">
              <button className="opacity-0 group-hover:opacity-100 transition-opacity px-4 py-2 bg-white rounded-md text-sm font-medium">
                View
              </button>
            </div>
          </div>
        ))}
      </div>

      {/* Lightbox Modal */}
      {selectedJob && (
        <div
          className="fixed inset-0 z-50 bg-black/80 flex items-center justify-center p-4"
          onClick={() => setSelectedJob(null)}
        >
          <div
            className="relative max-w-4xl w-full bg-white rounded-lg overflow-hidden"
            onClick={(e) => e.stopPropagation()}
          >
            <button
              onClick={() => setSelectedJob(null)}
              className="absolute top-4 right-4 z-10 p-2 bg-white rounded-full shadow-lg hover:bg-gray-100"
            >
              <X className="w-5 h-5" />
            </button>

            <div className="grid grid-cols-2 gap-4 p-6">
              {/* Input */}
              <div>
                <p className="text-sm font-medium text-gray-700 mb-2">Original</p>
                <div className="relative aspect-square">
                  <Image
                    src={selectedJob.input_image_url}
                    alt="Original"
                    fill
                    className="object-contain"
                  />
                </div>
              </div>

              {/* Result */}
              <div>
                <p className="text-sm font-medium text-gray-700 mb-2">Result</p>
                <div className="relative aspect-square">
                  <Image
                    src={selectedJob.result_image_url!}
                    alt="Result"
                    fill
                    className="object-contain"
                  />
                </div>
              </div>
            </div>

            <div className="border-t p-4 flex justify-end">
              <a
                href={selectedJob.result_image_url!}
                download
                className="px-4 py-2 bg-blue-500 text-white rounded-md hover:bg-blue-600 transition-colors inline-flex items-center"
              >
                <Download className="w-4 h-4 mr-2" />
                Download
              </a>
            </div>
          </div>
        </div>
      )}
    </>
  );
}
```

---

## 7. User Dashboard

Create `app/app/dashboard/page.tsx`:

```typescript
"use client";

import { useEffect, useState } from "react";
import { createClient } from "@/app/lib/supabase/client";
import { Batch } from "@/app/types";
import Link from "next/link";
import { Plus, Package, Shirt } from "lucide-react";
import { Button } from "@/app/components/ui/Button";

export default function DashboardPage() {
  const [batches, setBatches] = useState<Batch[]>([]);
  const [loading, setLoading] = useState(true);
  const supabase = createClient();

  useEffect(() => {
    loadBatches();
  }, []);

  async function loadBatches() {
    try {
      const { data, error } = await supabase
        .from("image_batches")
        .select("*")
        .order("created_at", { ascending: false })
        .limit(20);

      if (!error && data) {
        setBatches(data);
      }
    } catch (error) {
      console.error("Failed to load batches:", error);
    } finally {
      setLoading(false);
    }
  }

  if (loading) {
    return <div className="text-center py-12">Loading...</div>;
  }

  return (
    <div className="max-w-7xl mx-auto px-4 py-8">
      <div className="flex items-center justify-between mb-8">
        <h1 className="text-3xl font-bold">My Batches</h1>
        <Link href="/app/upload">
          <Button>
            <Plus className="w-4 h-4 mr-2" />
            New Batch
          </Button>
        </Link>
      </div>

      {batches.length === 0 ? (
        <div className="text-center py-12">
          <p className="text-gray-600 mb-4">No batches yet</p>
          <Link href="/app/upload">
            <Button>Create Your First Batch</Button>
          </Link>
        </div>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
          {batches.map((batch) => (
            <Link key={batch.id} href={`/app/batch/${batch.id}`}>
              <div className="bg-white p-6 rounded-lg shadow-md hover:shadow-lg transition-shadow cursor-pointer">
                <div className="flex items-start justify-between mb-4">
                  <div className="flex-1">
                    <h3 className="font-semibold text-lg mb-1">{batch.batch_name}</h3>
                    <p className="text-sm text-gray-600 flex items-center">
                      {batch.pipeline_mode === "objects" ? (
                        <Package className="w-4 h-4 mr-1" />
                      ) : (
                        <Shirt className="w-4 h-4 mr-1" />
                      )}
                      {batch.pipeline_mode}
                    </p>
                  </div>
                  <span
                    className={`px-3 py-1 rounded-full text-xs font-medium ${
                      batch.status === "completed"
                        ? "bg-green-100 text-green-800"
                        : batch.status === "processing"
                          ? "bg-blue-100 text-blue-800"
                          : "bg-red-100 text-red-800"
                    }`}
                  >
                    {batch.status}
                  </span>
                </div>

                <div className="grid grid-cols-3 gap-2 text-center text-sm">
                  <div>
                    <p className="font-semibold">{batch.total_images}</p>
                    <p className="text-gray-600">Total</p>
                  </div>
                  <div>
                    <p className="font-semibold text-green-600">{batch.completed_count}</p>
                    <p className="text-gray-600">Done</p>
                  </div>
                  <div>
                    <p className="font-semibold text-red-600">{batch.failed_count}</p>
                    <p className="text-gray-600">Failed</p>
                  </div>
                </div>

                <p className="text-xs text-gray-500 mt-4">
                  Created {new Date(batch.created_at).toLocaleDateString()}
                </p>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  );
}
```

---

## 8. Responsive Design

All components use Tailwind's responsive utilities:
- `sm:` - 640px and up
- `md:` - 768px and up
- `lg:` - 1024px and up
- `xl:` - 1280px and up

Example responsive grid:

```tsx
<div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
  {/* Cards */}
</div>
```

---

## 9. Component Testing

Create `__tests__/components/UploadForm.test.tsx`:

```typescript
import { render, screen, fireEvent } from "@testing-library/react";
import { UploadForm } from "@/app/components/upload/UploadForm";

describe("UploadForm", () => {
  it("renders pipeline selector", () => {
    render(<UploadForm />);
    expect(screen.getByText("Objects")).toBeInTheDocument();
    expect(screen.getByText("Clothing")).toBeInTheDocument();
  });

  it("disables submit when no files selected", () => {
    render(<UploadForm />);
    const submitButton = screen.getByRole("button", { name: /upload/i });
    expect(submitButton).toBeDisabled();
  });
});
```

---

## 10. Performance Optimization

### 10.1 Image Optimization

Use Next.js `<Image>` component with proper sizing:

```tsx
<Image
  src={url}
  alt="Description"
  width={300}
  height={300}
  quality={85}
  placeholder="blur"
/>
```

### 10.2 Code Splitting

Use dynamic imports for heavy components:

```typescript
const BatchMonitor = dynamic(() => import("@/app/components/batch/BatchMonitor"), {
  ssr: false,
  loading: () => <div>Loading...</div>,
});
```

---

## 11. Accessibility

- All interactive elements have proper ARIA labels
- Form inputs have associated labels
- Keyboard navigation support
- Color contrast ratios meet WCAG AA standards
- Focus indicators on all interactive elements

---

## 12. UI Component Library

### Button Component

Create `app/components/ui/Button.tsx`:

```typescript
import { ButtonHTMLAttributes, forwardRef } from "react";
import { clsx } from "clsx";

interface ButtonProps extends ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: "primary" | "secondary" | "danger";
  size?: "sm" | "md" | "lg";
}

export const Button = forwardRef<HTMLButtonElement, ButtonProps>(
  ({ children, className, variant = "primary", size = "md", ...props }, ref) => {
    return (
      <button
        ref={ref}
        className={clsx(
          "inline-flex items-center justify-center font-medium rounded-md transition-colors focus:outline-none focus:ring-2 focus:ring-offset-2",
          {
            "bg-blue-500 text-white hover:bg-blue-600 focus:ring-blue-500":
              variant === "primary",
            "bg-gray-200 text-gray-900 hover:bg-gray-300 focus:ring-gray-500":
              variant === "secondary",
            "bg-red-500 text-white hover:bg-red-600 focus:ring-red-500":
              variant === "danger",
            "px-3 py-1.5 text-sm": size === "sm",
            "px-4 py-2 text-base": size === "md",
            "px-6 py-3 text-lg": size === "lg",
            "opacity-50 cursor-not-allowed": props.disabled,
          },
          className
        )}
        {...props}
      >
        {children}
      </button>
    );
  }
);

Button.displayName = "Button";
```

### Input Component

Create `app/components/ui/Input.tsx`:

```typescript
import { InputHTMLAttributes, forwardRef } from "react";
import { clsx } from "clsx";

export const Input = forwardRef<
  HTMLInputElement,
  InputHTMLAttributes<HTMLInputElement>
>(({ className, ...props }, ref) => {
  return (
    <input
      ref={ref}
      className={clsx(
        "w-full px-4 py-2 border border-gray-300 rounded-md focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent disabled:opacity-50 disabled:cursor-not-allowed",
        className
      )}
      {...props}
    />
  );
});

Input.displayName = "Input";
```

### Badge Component

Create `app/components/ui/Badge.tsx`:

```typescript
import { ReactNode } from "react";
import { clsx } from "clsx";

interface BadgeProps {
  children: ReactNode;
  color?: "gray" | "blue" | "green" | "red" | "yellow";
}

export function Badge({ children, color = "gray" }: BadgeProps) {
  return (
    <span
      className={clsx(
        "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium",
        {
          "bg-gray-100 text-gray-800": color === "gray",
          "bg-blue-100 text-blue-800": color === "blue",
          "bg-green-100 text-green-800": color === "green",
          "bg-red-100 text-red-800": color === "red",
          "bg-yellow-100 text-yellow-800": color === "yellow",
        }
      )}
    >
      {children}
    </span>
  );
}
```

---

## Document Maintenance

**Last Updated:** February 12, 2026  
**Version:** 1.0  
**Maintainer:** Frontend Team  

**Related Documents:**
- [EXECUTION_PLAN.md](./EXECUTION_PLAN.md)
- [BE_EXECUTION.md](./BE_EXECUTION.md)
