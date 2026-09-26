ALTER TABLE public.reviews
  ADD COLUMN local_verified boolean NOT NULL DEFAULT false,
  ADD COLUMN proof_id uuid,
  ADD COLUMN verification_method text;

CREATE TABLE public.review_proofs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  review_id uuid NOT NULL UNIQUE REFERENCES public.reviews(id) ON DELETE CASCADE,
  user_id uuid NOT NULL,
  spot_id text NOT NULL,
  address_id uuid NOT NULL,
  distance_km double precision NOT NULL,
  previous_hash text,
  proof_hash text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now()
);
GRANT ALL ON public.review_proofs TO service_role;
ALTER TABLE public.review_proofs ENABLE ROW LEVEL SECURITY;

ALTER TABLE public.reviews
  ADD CONSTRAINT reviews_proof_id_fkey
  FOREIGN KEY (proof_id) REFERENCES public.review_proofs(id) ON DELETE SET NULL,
  ADD CONSTRAINT reviews_verification_method_check
  CHECK (verification_method IS NULL OR verification_method = 'home_radius_hash_chain');

REVOKE INSERT, UPDATE ON public.reviews FROM authenticated;

CREATE OR REPLACE FUNCTION public.create_verified_review(
  _user_id uuid,
  _spot_id text,
  _spot_name text,
  _rating integer,
  _body text,
  _reviewer_type text,
  _spot_lat double precision,
  _spot_lng double precision,
  _address_id uuid DEFAULT NULL,
  _author_name text DEFAULT NULL
)
RETURNS public.reviews
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  _review public.reviews;
  _address public.addresses;
  _distance double precision;
  _proof_id uuid;
  _previous_hash text;
  _proof_hash text;
  _created_at timestamptz := clock_timestamp();
BEGIN
  IF _rating < 1 OR _rating > 5 THEN
    RAISE EXCEPTION 'Rating must be between 1 and 5.';
  END IF;
  IF char_length(trim(_body)) < 3 OR char_length(trim(_body)) > 1200 THEN
    RAISE EXCEPTION 'Review must be between 3 and 1200 characters.';
  END IF;
  IF _reviewer_type NOT IN ('local', 'visitor') THEN
    RAISE EXCEPTION 'Choose Local or Tourist.';
  END IF;

  IF _reviewer_type = 'local' THEN
    SELECT * INTO _address
    FROM public.addresses
    WHERE id = _address_id
      AND user_id = _user_id
      AND lower(trim(label)) = 'home';

    IF NOT FOUND THEN
      RAISE EXCEPTION 'Choose a saved address labelled Home to verify as a local.';
    END IF;

    _distance := 6371 * 2 * asin(sqrt(
      power(sin(radians(_spot_lat - _address.lat) / 2), 2) +
      cos(radians(_address.lat)) * cos(radians(_spot_lat)) *
      power(sin(radians(_spot_lng - _address.lng) / 2), 2)
    ));

    IF _distance > 10 THEN
      RAISE EXCEPTION 'Your saved Home address must be within 10 km of this place.';
    END IF;
  END IF;

  INSERT INTO public.reviews (
    user_id, spot_id, spot_name, rating, body, reviewer_type,
    author_name, distance_km, local_verified, verification_method, created_at
  ) VALUES (
    _user_id, _spot_id, _spot_name, _rating, trim(_body), _reviewer_type,
    _author_name, CASE WHEN _reviewer_type = 'local' THEN _distance ELSE NULL END,
    _reviewer_type = 'local',
    CASE WHEN _reviewer_type = 'local' THEN 'home_radius_hash_chain' ELSE NULL END,
    _created_at
  ) RETURNING * INTO _review;

  IF _reviewer_type = 'local' THEN
    SELECT proof_hash INTO _previous_hash
    FROM public.review_proofs
    ORDER BY created_at DESC, id DESC
    LIMIT 1
    FOR UPDATE;

    _proof_id := gen_random_uuid();
    _proof_hash := encode(extensions.digest(
      concat_ws('|', coalesce(_previous_hash, 'GENESIS'), _proof_id::text,
        _review.id::text, _user_id::text, _spot_id, _address.id::text,
        round(_distance::numeric, 6)::text, _created_at::text),
      'sha256'
    ), 'hex');

    INSERT INTO public.review_proofs (
      id, review_id, user_id, spot_id, address_id, distance_km,
      previous_hash, proof_hash, created_at
    ) VALUES (
      _proof_id, _review.id, _user_id, _spot_id, _address.id, _distance,
      _previous_hash, _proof_hash, _created_at
    );

    UPDATE public.reviews SET proof_id = _proof_id WHERE id = _review.id
    RETURNING * INTO _review;
  END IF;

  RETURN _review;
END;
$$;

REVOKE ALL ON FUNCTION public.create_verified_review(uuid, text, text, integer, text, text, double precision, double precision, uuid, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_verified_review(uuid, text, text, integer, text, text, double precision, double precision, uuid, text) FROM anon;
REVOKE ALL ON FUNCTION public.create_verified_review(uuid, text, text, integer, text, text, double precision, double precision, uuid, text) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.create_verified_review(uuid, text, text, integer, text, text, double precision, double precision, uuid, text) TO service_role;