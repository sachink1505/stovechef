-- Platform recipes: allow AI-seeded recipes with no owner and no source video.
-- Adds category/region for browse catalog filtering and a read policy so all
-- authenticated users can see platform recipes.

ALTER TABLE recipes ALTER COLUMN created_by DROP NOT NULL;
ALTER TABLE recipes ALTER COLUMN video_url DROP NOT NULL;
ALTER TABLE recipes ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE recipes ADD COLUMN IF NOT EXISTS region TEXT;

DROP POLICY IF EXISTS "Platform recipes readable by all authenticated users" ON recipes;
CREATE POLICY "Platform recipes readable by all authenticated users"
  ON recipes FOR SELECT
  TO authenticated
  USING (is_platform_recipe = true);
