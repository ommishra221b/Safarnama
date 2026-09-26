-- 1. Remove duplicate saved addresses, keeping the default (or oldest) row.
WITH ranked AS (
  SELECT id,
         row_number() OVER (
           PARTITION BY user_id, lower(btrim(full_address))
           ORDER BY is_default DESC, created_at ASC
         ) AS rn
  FROM public.addresses
)
DELETE FROM public.addresses a
USING ranked r
WHERE a.id = r.id AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS addresses_user_address_unique
  ON public.addresses (user_id, lower(btrim(full_address)));

-- 2. Travel history
CREATE TABLE IF NOT EXISTS public.travel_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL,
  spot_id TEXT NOT NULL,
  spot_name TEXT NOT NULL,
  spot_area TEXT,
  spot_city TEXT,
  mode TEXT NOT NULL,
  distance_km NUMERIC(8,2) NOT NULL DEFAULT 0,
  duration_min INTEGER,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS travel_history_user_created_idx
  ON public.travel_history (user_id, created_at DESC);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.travel_history TO authenticated;
GRANT ALL ON public.travel_history TO service_role;

ALTER TABLE public.travel_history ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users read own travel history" ON public.travel_history;
CREATE POLICY "Users read own travel history" ON public.travel_history
  FOR SELECT TO authenticated USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users insert own travel history" ON public.travel_history;
CREATE POLICY "Users insert own travel history" ON public.travel_history
  FOR INSERT TO authenticated WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "Users delete own travel history" ON public.travel_history;
CREATE POLICY "Users delete own travel history" ON public.travel_history
  FOR DELETE TO authenticated USING (auth.uid() = user_id);
