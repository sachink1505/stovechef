# Changelog

All notable changes to StoveChef are documented here.
Format: `[YYYY-MM-DD] — commit hash — description`

---

## 2026-04-09 — `302619d` — Backend code review fixes

**Security**
- Moved Gemini API key from URL query parameter to `x-goog-api-key` header to prevent key exposure in proxy/server logs

**Bug Fixes**
- Added bounds checking on Gemini API response (`candidates` and `parts` lists) to prevent unhandled `RangeError` crashes on empty or malformed responses
- Fixed silent cache error swallowing in `cache_service.dart` — `TimeoutException` and `FormatException` are now handled separately with logging; corrupted entries are cleared automatically
- Fixed timer to use `Stopwatch` for elapsed time instead of `DateTime.now()`, preventing drift from system clock changes (DST, NTP sync)

**Performance / Reliability**
- Replaced fixed retry delay with exponential backoff + jitter (2s → 4s → 8s, plus up to 5s random jitter) to prevent thundering herd on failures
- Added 5-second timeouts on all Hive operations to prevent UI hangs on slow/corrupt devices
- Made daily recipe limit check atomic via a new Postgres RPC (`check_and_increment_daily_limit`) that checks and increments in a single transaction — prevents concurrent requests from bypassing the limit
- Added SQL migration: `supabase/migrations/001_check_and_increment_daily_limit.sql`

**Code Quality**
- Removed duplicate `_UrlUtils` class from `recipe_creation_service.dart`; now imports from `lib/utils/url_utils.dart` directly
- Added `kDebugMode` debug logging across `supabase_service`, `recipe_generator_service`, `recipe_creation_service`, and `cache_service`

---

## 2026-04-09 — `2317805` — README update

- Rewrote README with product overview, how it works, tech stack table, getting started instructions, features list, and project structure

---

## 2026-04-09 — `287355a` — Initial commit

**App**
- Full Flutter app implementation for iOS and Android

**Auth**
- Email OTP authentication via Supabase (6-digit code)
- GoRouter with auth redirect logic and session persistence
- Personal details screen (name + food preference) on first login

**Recipe Creation**
- YouTube URL canonicalization (supports youtu.be, Shorts, mobile, embed)
- Transcript extraction from YouTube caption tracks
- Gemini 2.0 Flash integration for structured recipe generation
- Progress screen with stage-by-stage status messages
- Duplicate detection — reuses existing recipe if same video submitted again
- Daily generation limit (configurable, default 5/day)

**Recipe Screen**
- Ingredient list with quantities, prep methods, and regional aliases
- Preparation steps list
- Expandable step cards with timer, flame level, and per-step ingredients
- Parallax header image via SliverAppBar + FlexibleSpaceBar
- Shimmer loading skeleton
- Staggered entry animations

**Cooking Mode**
- Full-screen step-by-step guided cooking
- Countdown timers with sound + haptic feedback on completion
- Flame level indicator per step
- Prep steps with "Mark done" — grays out with green tick on completion
- Skip step support
- Progress saved to disk — resume where you left off after closing app
- Offline support via Hive cache

**Offline & Connectivity**
- Offline banner (amber strip) shown when network is unavailable
- Cache-first loading for recipes and cooking state
- `connectivity_plus` service with stream-based online status

**Profile**
- Avatar with initial letter fallback
- Phone number add/edit via bottom sheet
- My Creations with paginated list (10 per page), newest first
- Logout with confirm dialog + cache clear

**Infrastructure**
- Riverpod `ProviderScope` with 6 service providers
- Hive local cache for recipes, cooking states, and preferences
- `build.sh` release build script (APK + AAB)
- `.env.example` documenting required environment variables
- `DEPLOYMENT.md` with Play Store + App Store submission guide
- Android: `minSdk=21`, `targetSdk=34`, core library desugaring enabled
- iOS: portrait-only, notification usage description, audio background mode

**Tests**
- `test/url_utils_test.dart` — 39 automated tests for URL canonicalization
- `test/smoke_test.dart` — printable manual checklist for 6 end-to-end flows
