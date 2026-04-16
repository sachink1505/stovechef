import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
import OpenAI from 'openai';
import sharp from 'sharp';
import pLimit from 'p-limit';

// ── Config ────────────────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const OPENAI_API_KEY = process.env.OPENAI_API_KEY!;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !OPENAI_API_KEY) {
  console.error('Missing env vars: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, OPENAI_API_KEY');
  process.exit(1);
}

const BUCKET = 'recipe-images';
const MODEL = 'gpt-image-1';
const QUALITY = 'medium';
const SIZE = '1024x1024';
const CONCURRENCY = 3;
const COST_PER_IMAGE_USD = 0.042;

// ── Args ──────────────────────────────────────────────────────

function getArg(name: string): string | undefined {
  const eq = process.argv.find(a => a.startsWith(`--${name}=`));
  if (eq) return eq.split('=')[1];
  const idx = process.argv.indexOf(`--${name}`);
  if (idx >= 0) return process.argv[idx + 1];
  return undefined;
}

const limitArg = parseInt(getArg('limit') ?? '10', 10);
const offsetArg = parseInt(getArg('offset') ?? '0', 10);
const dryRun = process.argv.includes('--dry-run');

// ── Clients ───────────────────────────────────────────────────

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
const openai = new OpenAI({ apiKey: OPENAI_API_KEY });

// ── Bucket setup ──────────────────────────────────────────────

async function ensureBucket() {
  const { data: buckets, error } = await supabase.storage.listBuckets();
  if (error) throw new Error(`listBuckets failed: ${error.message}`);
  if (buckets?.some(b => b.name === BUCKET)) return;

  const { error: createErr } = await supabase.storage.createBucket(BUCKET, {
    public: true,
    fileSizeLimit: 2 * 1024 * 1024,
  });
  if (createErr) throw new Error(`createBucket failed: ${createErr.message}`);
  console.log(`✓ Created public bucket "${BUCKET}"`);
}

// ── Prompt ────────────────────────────────────────────────────

function buildImagePrompt(name: string, category: string | null, ingredients: any[]): string {
  const topIngredients = (ingredients ?? [])
    .slice(0, 3)
    .map((i: any) => (typeof i === 'string' ? i : i?.name))
    .filter(Boolean)
    .join(', ');
  const cat = category ? `, a traditional Indian ${category.toLowerCase()} dish` : '';
  const ing = topIngredients ? ` featuring ${topIngredients}` : '';
  return `Overhead food photography of "${name}"${cat}${ing}, served in a traditional Indian bowl or thali on a rustic wooden table, garnished authentically, soft natural lighting, shallow depth of field, vibrant colors, appetizing, magazine quality, no text, no watermark, no hands, no utensils in frame.`;
}

// ── Generate + upload one ─────────────────────────────────────

type Recipe = { id: string; title: string; category: string | null; ingredients: any };

async function processRecipe(r: Recipe, idx: number, total: number): Promise<'ok' | 'error'> {
  const label = `[${idx}/${total}] ${r.title}`;
  try {
    const prompt = buildImagePrompt(r.title, r.category, r.ingredients ?? []);

    const img = await withRetry(() =>
      openai.images.generate({
        model: MODEL,
        prompt,
        size: SIZE as any,
        quality: QUALITY as any,
        n: 1,
      })
    );

    const b64 = img.data?.[0]?.b64_json;
    if (!b64) throw new Error('no b64_json in OpenAI response');
    const rawBuf = Buffer.from(b64, 'base64');

    const webpBuf = await sharp(rawBuf)
      .resize(1024, 1024, { fit: 'cover' })
      .webp({ quality: 80 })
      .toBuffer();

    const path = `platform/${r.id}.webp`;
    const { error: upErr } = await supabase.storage
      .from(BUCKET)
      .upload(path, webpBuf, { upsert: true, contentType: 'image/webp' });
    if (upErr) throw new Error(`upload: ${upErr.message}`);

    const { data: pub } = supabase.storage.from(BUCKET).getPublicUrl(path);
    const publicUrl = pub.publicUrl;

    const { error: updErr } = await supabase
      .from('recipes')
      .update({ thumbnail_url: publicUrl })
      .eq('id', r.id);
    if (updErr) throw new Error(`update: ${updErr.message}`);

    console.log(`  ✓ ${label} → ${publicUrl}`);
    return 'ok';
  } catch (e: any) {
    console.error(`  ✗ ${label}: ${e.message}`);
    return 'error';
  }
}

async function withRetry<T>(fn: () => Promise<T>): Promise<T> {
  try {
    return await fn();
  } catch (e) {
    await new Promise(r => setTimeout(r, 2000));
    return await fn();
  }
}

// ── Main ──────────────────────────────────────────────────────

async function main() {
  console.log(`\n🎨 StoveChef Image Generator — OpenAI ${MODEL} (${QUALITY}, ${SIZE})`);
  console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`limit=${limitArg} offset=${offsetArg} concurrency=${CONCURRENCY}${dryRun ? ' (DRY RUN)' : ''}\n`);

  await ensureBucket();

  const { data: recipes, error } = await supabase
    .from('recipes')
    .select('id, title, category, ingredients')
    .eq('is_platform_recipe', true)
    .is('thumbnail_url', null)
    .order('created_at', { ascending: true })
    .range(offsetArg, offsetArg + limitArg - 1);

  if (error) {
    console.error(`Query failed: ${error.message}`);
    process.exit(1);
  }
  if (!recipes || recipes.length === 0) {
    console.log('No platform recipes missing thumbnail_url. Nothing to do.');
    return;
  }

  console.log(`Found ${recipes.length} recipes to process.`);
  console.log(`Estimated cost: $${(recipes.length * COST_PER_IMAGE_USD).toFixed(2)}\n`);

  if (dryRun) {
    recipes.forEach((r, i) => console.log(`  [${i + 1}] ${r.title}`));
    return;
  }

  const limit = pLimit(CONCURRENCY);
  const total = recipes.length;
  let ok = 0;
  let err = 0;

  await Promise.all(
    recipes.map((r, i) =>
      limit(async () => {
        const result = await processRecipe(r as Recipe, i + 1, total);
        if (result === 'ok') ok++;
        else err++;
      })
    )
  );

  const spent = ok * COST_PER_IMAGE_USD;
  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`Done: ${ok} succeeded, ${err} failed`);
  console.log(`Estimated spend: $${spent.toFixed(2)}`);
  console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`);
}

main().catch(e => {
  console.error(e);
  process.exit(1);
});
