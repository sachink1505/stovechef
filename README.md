# StoveChef

Turn any YouTube cooking video into a guided, step-by-step recipe you can follow on your gas stove — without pausing, rewinding, or squinting at your screen.

---

## What it does

Paste a YouTube cooking video link. StoveChef extracts the transcript, understands the recipe, and converts it into a structured, interactive guide with:

- A clean ingredient list with quantities and prep methods
- Step-by-step cooking instructions in the right order
- Built-in countdown timers that fire a sound and notification when a step is done
- Flame level indicators (low / medium / high) for every cooking step
- Offline access once a recipe is loaded — works fully without internet in the kitchen

---

## Why it's useful

Cooking from a YouTube video is frustrating. You pause, rewind, try to remember quantities, lose your place, and end up with sauce on your phone screen.

StoveChef removes all of that:

- **No more pausing** — every step, timer, and quantity is already extracted
- **Hands-free cooking** — audio alerts tell you when a timer is done
- **Kitchen-friendly UI** — large tap targets designed for wet or dirty hands
- **Works offline** — once generated, your recipe is cached locally

---

## How it works

1. **Paste a YouTube link** — any cooking video (standard, Shorts, or youtu.be links)
2. **StoveChef extracts** the transcript from YouTube's caption track
3. **Gemini AI parses** the transcript into structured ingredients and steps
4. **The recipe is saved** to your account and cached on your device
5. **Start cooking** — tap through each step, let timers run, mark steps done

```
YouTube URL → Transcript → Gemini AI → Structured Recipe → Guided Cooking Mode
```

---

## Tech stack

| Layer | Technology |
|---|---|
| Mobile app | Flutter (iOS + Android) |
| Backend / Auth / DB | Supabase (PostgreSQL + Auth) |
| AI recipe generation | Google Gemini 2.0 Flash |
| Local caching | Hive |
| Navigation | GoRouter |
| State management | Riverpod |

---

## Getting started

### Prerequisites

- Flutter SDK 3.x
- A [Supabase](https://supabase.com) project with migrations applied
- A [Gemini API key](https://aistudio.google.com/apikey)

### Run locally

```bash
flutter pub get

flutter run \
  --dart-define=SUPABASE_URL=https://your-project.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=eyJ... \
  --dart-define=GEMINI_API_KEY=AIzaSy...
```

### Build for release

```bash
export SUPABASE_URL=https://your-project.supabase.co
export SUPABASE_ANON_KEY=eyJ...
export GEMINI_API_KEY=AIzaSy...

./build.sh
```

See [DEPLOYMENT.md](DEPLOYMENT.md) for full Play Store and App Store submission instructions.

---

## Features

- Email OTP authentication (no passwords)
- Recipe creation from any YouTube cooking video
- Ingredient list with regional name aliases (English, Hindi, Tamil, Telugu, Kannada)
- Cooking mode with step timers, flame levels, and haptic feedback
- Skip steps, resume where you left off
- Search your recipe library
- Daily recipe generation limit (configurable)
- Offline cooking mode
- Portrait-only, kitchen-optimised UI

---

## Project structure

```
lib/
├── config/        # Theme, env vars, providers
├── models/        # Recipe, Step, Ingredient, UserProfile
├── screens/       # All app screens
├── services/      # Supabase, Gemini, Transcript, Cache, Notifications
├── utils/         # URL canonicalization
└── widgets/       # Reusable UI components
```
