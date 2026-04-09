# StoveChef — Build Learnings

Lessons from building StoveChef (YouTube → guided recipe app) that apply to future projects.

---

## Things to Avoid

### 1. Don't trust third-party scraping libraries blindly
`youtube_explode_dart` returned HTTP 200 with empty bodies for captions, 403 for audio streams, and has aggressive internal retry loops that made debugging noisy. Client-side scraping libraries break whenever the upstream platform changes something.

**Instead:** For production, use official APIs (YouTube Data API v3) or move extraction server-side (e.g., Supabase Edge Function) where you have more control, logging, and can swap implementations without an app update.

### 2. Don't assume free-tier APIs will stay free or available
- Gemini free tier was blocked regionally (India) with `limit: 0` on all models
- `gemini-2.0-flash` got deprecated mid-development
- `gemini-2.5-flash` had intermittent 503s (high demand)

**Instead:** Enable billing from day one (even if usage stays at $0). Don't hardcode model names — make them configurable via remote config or environment variables.

### 3. Don't cache auth/profile state with lazy evaluation
GoRouter's redirect cached `_profileComplete` using `??=` and never re-evaluated after the user completed their profile. The router kept redirecting away from `/home` silently.

**Instead:** Always invalidate caches explicitly after state mutations. Prefer reactive patterns (streams, listeners) over lazy-cached booleans for auth state.

### 4. Don't upsert without checking all NOT NULL columns
The profile upsert omitted the `email` column, which had a NOT NULL constraint in Supabase. The error (`PostgrestException code 23502`) was opaque until we added debug logging.

**Instead:** Before writing any upsert, verify the actual table schema. Log the full payload and error details on failure.

### 5. Don't build without logging from the start
We added logging reactively after things broke. The caption issue (HTTP 200 with 0 bytes body) would have been caught immediately with proper logging.

**Instead:** Every service should have `_log()` calls at entry/exit of public methods, HTTP status codes, response sizes, and timing from the very first commit.

### 6. Don't use a single caption format
YouTube's `srv1` (XML) format returned empty bodies for some videos. The `json3` format worked where `srv1` didn't.

**Instead:** Always implement a fallback chain for unreliable external data. In our case: json3 → srv1 XML → audio-to-Gemini.

---

## Where More Clarity Was Needed

### Transcript extraction strategy
Client-side vs server-side? Client-side is cheaper but fragile. Server-side (Edge Function + official API) is more reliable and lets you iterate without app updates. Decide this upfront.

### AI model selection and cost management
- What's the monthly budget?
- Should the model be switchable via remote config?
- Should recipe generation be queued server-side to control costs?
- How to handle model deprecations without an app update?

### Offline behavior boundaries
The spec said "recipes should be usable offline in cooking mode" but the exact scope was unclear — just cooking mode, or also browsing saved recipes? Define offline boundaries before building.

### Error UX design
The spec said "use images/icons wherever possible" for errors, but many error states were left as plain text. Error screens need design attention upfront — what does the user see when YouTube blocks a video, Gemini is overloaded, or the daily limit is hit?

---

## Patterns Worth Repeating

### 1. Dev/build scripts with env validation
`run_dev.sh` and `build.sh` validate that all required environment variables are present before running. Catches missing API keys before runtime. Do this for every project with secrets.

### 2. Atomic RPC for rate limiting
`check_and_increment_daily_limit` uses a single Supabase RPC that checks and increments in one transaction, preventing race conditions from concurrent requests. Good pattern for any user-facing quota.

### 3. Canonical URL deduplication
Normalizing YouTube URLs (strip tracking params, normalize youtu.be vs youtube.com, ignore timestamps) before DB lookup prevents duplicate recipe generation. Apply this to any user-submitted URL input.

### 4. Graceful format fallback chains
Caption fetching tries json3 → srv1 → audio download. Each step fails gracefully and hands off to the next. Good pattern for any unreliable external data source.

### 5. `--dart-define` for compile-time secrets
Using `String.fromEnvironment()` with `--dart-define` keeps secrets out of source code. Combined with a `.env` file (gitignored) and a sourcing script, this is a clean pattern for Flutter apps.

---

## If Starting This Project Over

1. **Put AI calls behind a server-side function** (Supabase Edge Function) from day one — hides API key, lets you switch models without app updates, adds request logging and cost monitoring
2. **Use YouTube Data API v3** (official, with API key) for metadata + caption list instead of client-side scraping
3. **Add structured logging with timestamps** from the first commit, not reactively after things break
4. **Set up billing on all external APIs immediately** — don't rely on free tiers during development
5. **Make AI model name a remote config value**, not a hardcoded string — models get deprecated without warning
6. **Define offline boundaries** in the spec before writing any code
7. **Design error screens** alongside happy-path screens, not as an afterthought
