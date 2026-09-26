CREATE TABLE public.plan_reviews (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  plan_id TEXT NOT NULL,
  plan_title TEXT NOT NULL,
  rating SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
  body TEXT NOT NULL,
  author_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.plan_reviews TO authenticated;
GRANT SELECT ON public.plan_reviews TO anon;
GRANT ALL ON public.plan_reviews TO service_role;

ALTER TABLE public.plan_reviews ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Anyone can read plan reviews"
  ON public.plan_reviews FOR SELECT
  USING (true);

CREATE POLICY "Users can add their own plan reviews"
  ON public.plan_reviews FOR INSERT TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can update their own plan reviews"
  ON public.plan_reviews FOR UPDATE TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own plan reviews"
  ON public.plan_reviews FOR DELETE TO authenticated
  USING (auth.uid() = user_id);

CREATE INDEX plan_reviews_plan_id_idx ON public.plan_reviews (plan_id);