-- Migration: Add check_and_increment_daily_limit RPC
--
-- Replaces the two-step check + increment pattern (which had a race condition)
-- with a single atomic transaction. Returns the current count, configured limit,
-- and whether the request is allowed — incrementing only if allowed.
--
-- Run this in Supabase SQL Editor or via the Supabase CLI.

CREATE OR REPLACE FUNCTION check_and_increment_daily_limit(
  p_user_id UUID,
  p_date    DATE
)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count  INT;
  v_limit  INT;
  v_allowed BOOLEAN;
  v_limit_str TEXT;
BEGIN
  -- Read configurable limit from app_config table (falls back to 5).
  SELECT value INTO v_limit_str
  FROM app_config
  WHERE key = 'daily_recipe_limit';

  v_limit := COALESCE(v_limit_str::INT, 5);

  -- Lock the user's row for this date to prevent concurrent races.
  -- ON CONFLICT ensures the row exists before we read it.
  INSERT INTO daily_generation_log (user_id, generation_date, count)
  VALUES (p_user_id, p_date, 0)
  ON CONFLICT (user_id, generation_date) DO NOTHING;

  SELECT count INTO v_count
  FROM daily_generation_log
  WHERE user_id = p_user_id
    AND generation_date = p_date
  FOR UPDATE;

  v_allowed := v_count < v_limit;

  IF v_allowed THEN
    UPDATE daily_generation_log
    SET count = count + 1
    WHERE user_id = p_user_id
      AND generation_date = p_date;

    v_count := v_count + 1;
  END IF;

  RETURN json_build_object(
    'count',   v_count,
    'limit',   v_limit,
    'allowed', v_allowed
  );
END;
$$;

-- Grant execute to authenticated users only.
REVOKE ALL ON FUNCTION check_and_increment_daily_limit(UUID, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION check_and_increment_daily_limit(UUID, DATE) TO authenticated;
