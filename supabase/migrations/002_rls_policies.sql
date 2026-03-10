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