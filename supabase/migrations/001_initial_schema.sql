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
                                   pipeline_type TEXT NOT NULL CHECK (pipeline_type IN ('background_removal', 'background_generation', 'lighting_unification', 'virtual_tryon')),

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