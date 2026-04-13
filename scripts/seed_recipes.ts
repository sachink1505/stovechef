import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';
import { GoogleGenerativeAI } from '@google/generative-ai';
import { RECIPES } from './recipe_list.ts';

// ── Config ────────────────────────────────────────────────────

const SUPABASE_URL = process.env.SUPABASE_URL!;
const SUPABASE_SERVICE_ROLE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY!;
const GEMINI_API_KEY = process.env.GEMINI_API_KEY!;

if (!SUPABASE_URL || !SUPABASE_SERVICE_ROLE_KEY || !GEMINI_API_KEY) {
  console.error('Missing env vars: SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, GEMINI_API_KEY');
  process.exit(1);
}

const BATCH_SIZE = 100;
const GROUP_SIZE = 5;       // concurrent Gemini calls per group
const GROUP_DELAY_MS = 2000; // delay between groups

// ── Parse --batch arg ─────────────────────────────────────────

const batchArg = process.argv.find(a => a.startsWith('--batch=') || a === '--batch');
let batchNum = 1;
if (batchArg) {
  const val = batchArg.includes('=')
    ? batchArg.split('=')[1]
    : process.argv[process.argv.indexOf('--batch') + 1];
  batchNum = parseInt(val, 10);
  if (isNaN(batchNum) || batchNum < 1 || batchNum > 5) {
    console.error('--batch must be 1–5');
    process.exit(1);
  }
}

const startIdx = (batchNum - 1) * BATCH_SIZE;
const endIdx = Math.min(startIdx + BATCH_SIZE, RECIPES.length);
const batchRecipes = RECIPES.slice(startIdx, endIdx);

console.log(`\n🍛 StoveChef Seeder — Batch ${batchNum} (recipes ${startIdx + 1}–${endIdx} of ${RECIPES.length})`);
console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`);

// ── Clients ───────────────────────────────────────────────────

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
const genAI = new GoogleGenerativeAI(GEMINI_API_KEY);
const model = genAI.getGenerativeModel({
  model: 'gemini-2.5-flash-lite',
  generationConfig: { temperature: 0.1, maxOutputTokens: 8192, responseMimeType: 'application/json' },
});

// ── Helpers ───────────────────────────────────────────────────

function slugify(name: string): string {
  return name.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function buildPrompt(recipeName: string): string {
  return `You are an expert Indian home cook and culinary writer. Generate a complete, authentic, detailed recipe for "${recipeName}" as if it were extracted from a popular Indian cooking video.

Return ONLY valid JSON (no markdown, no backticks) with this exact structure:
{
  "title": "${recipeName}",
  "cooking_time_minutes": 30,
  "portion_size": 2,
  "ingredients": [
    {
      "name": "Onion",
      "quantity": "2 large (approx. 200g)",
      "prep_method": "finely chopped",
      "aliases": {"hindi": "pyaaz", "tamil": "vengayam", "telugu": "ullipaya", "kannada": "eerulli"}
    }
  ],
  "preparations": [
    "Soak rajma overnight in water"
  ],
  "steps": [
    {
      "step_number": 1,
      "title": "Chop vegetables",
      "description": "Finely chop 2 onions, mince 4 cloves of garlic, and dice 2 tomatoes.",
      "timer_seconds": null,
      "flame_level": null,
      "is_prep": true,
      "ingredients": [
        {"name": "Onion", "quantity": "2 large (approx. 200g)", "prep_method": "finely chopped"}
      ]
    },
    {
      "step_number": 2,
      "title": "Add oil to pan",
      "description": "Add 2 tablespoons of oil to a heavy-bottomed pan.",
      "timer_seconds": null,
      "flame_level": null,
      "is_prep": true,
      "ingredients": [{"name": "Oil", "quantity": "2 tablespoons (30ml)", "prep_method": null}]
    },
    {
      "step_number": 3,
      "title": "Heat oil",
      "description": "Heat the oil on medium flame for 30 seconds until it shimmers.",
      "timer_seconds": 30,
      "flame_level": "medium",
      "is_prep": false,
      "ingredients": []
    }
  ]
}

Rules:
- portion_size: default to 2.
- STEP SPLITTING: Every cooking action MUST be split into TWO separate steps:
  1. An "add/pour/put" step (is_prep: true, no timer, no flame) where ingredients are added to the pan.
  2. A "cook/heat/fry/boil" step (is_prep: false, with timer_seconds and flame_level) where actual cooking happens.
- timer_seconds: ONLY for cooking steps involving heat. null for prep/add steps.
- flame_level: ONLY "low", "medium", or "high". null for prep/add steps.
- is_prep: true for steps with no cooking (chopping, mixing, adding ingredients). false ONLY for heat/cooking steps.
- ALTERNATIVE MEASUREMENTS: For every quantity, provide metric measurement in parentheses e.g. "2 tablespoons (30ml)", "1 cup (240ml)", "2 large (approx. 200g)".
- ingredients: include regional aliases in Hindi, Tamil, Telugu, and Kannada.
- preparations: list things to do before cooking starts (soaking, marinating, etc.). Empty array if none.
- Be precise with quantities. Generate an authentic, complete recipe.
- cooking_time_minutes: realistic total cooking time (not prep time).`;
}

// ── Check existing ────────────────────────────────────────────

async function alreadyExists(canonicalUrl: string): Promise<boolean> {
  const { data } = await supabase
    .from('recipes')
    .select('id')
    .eq('canonical_url', canonicalUrl)
    .maybeSingle();
  return data !== null;
}

// ── Generate & insert ─────────────────────────────────────────

async function seedRecipe(name: string, category: string, region: string): Promise<'inserted' | 'skipped' | 'error'> {
  const canonicalUrl = `platform://recipe/${slugify(name)}`;

  if (await alreadyExists(canonicalUrl)) {
    return 'skipped';
  }

  let recipeJson: any;
  try {
    const result = await model.generateContent(buildPrompt(name));
    const text = result.response.text();
    recipeJson = JSON.parse(text);
  } catch (e: any) {
    console.error(`  ✗ Gemini error for "${name}": ${e.message}`);
    return 'error';
  }

  const row = {
    video_url: null,
    canonical_url: canonicalUrl,
    title: recipeJson.title ?? name,
    creator_name: 'StoveChef',
    thumbnail_url: null,
    cooking_time_minutes: recipeJson.cooking_time_minutes ?? 30,
    portion_size: recipeJson.portion_size ?? 2,
    is_platform_recipe: true,
    created_by: null,
    ingredients: recipeJson.ingredients ?? [],
    preparations: recipeJson.preparations ?? [],
    steps: recipeJson.steps ?? [],
    category,
    region,
  };

  const { error } = await supabase.from('recipes').insert(row);
  if (error) {
    console.error(`  ✗ Insert error for "${name}": ${error.message}`);
    return 'error';
  }

  return 'inserted';
}

// ── Main ──────────────────────────────────────────────────────

async function main() {
  let inserted = 0;
  let skipped = 0;
  let errors = 0;
  const total = batchRecipes.length;

  for (let i = 0; i < total; i += GROUP_SIZE) {
    const group = batchRecipes.slice(i, i + GROUP_SIZE);

    const results = await Promise.all(
      group.map(async (r, j) => {
        const idx = i + j + 1;
        const result = await seedRecipe(r.name, r.category, r.region);
        const icon = result === 'inserted' ? '✓' : result === 'skipped' ? '→' : '✗';
        console.log(`  [Batch ${batchNum} | ${idx}/${total}] ${icon} ${r.name}`);
        return result;
      })
    );

    results.forEach(r => {
      if (r === 'inserted') inserted++;
      else if (r === 'skipped') skipped++;
      else errors++;
    });

    if (i + GROUP_SIZE < total) {
      await new Promise(resolve => setTimeout(resolve, GROUP_DELAY_MS));
    }
  }

  console.log(`\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━`);
  console.log(`Batch ${batchNum} complete: ${inserted} inserted, ${skipped} skipped, ${errors} errors`);
  console.log(`━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n`);
}

main().catch(console.error);
