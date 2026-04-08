// This is a manual checklist runner — not an automated test.
// Run with: dart test/smoke_test.dart
//
// It prints a structured checklist to stdout that you follow while running
// the app on a device or simulator.

// ignore_for_file: avoid_print

void main() {
  _printChecklist();
}

void _printChecklist() {
  const lines = '''
╔══════════════════════════════════════════════════════════════════╗
║              StoveChef Smoke Test Checklist                      ║
╚══════════════════════════════════════════════════════════════════╝

PRE-REQUISITES:
  [ ] Supabase project is running
  [ ] SQL migrations have been applied
  [ ] Gemini API key is valid
  [ ] Run with:
        flutter run \\
          --dart-define=SUPABASE_URL=<your_url> \\
          --dart-define=SUPABASE_ANON_KEY=<your_key> \\
          --dart-define=GEMINI_API_KEY=<your_key>

──────────────────────────────────────────────────────────────────
FLOW 1 — Onboarding
──────────────────────────────────────────────────────────────────
  [ ] App opens to Welcome Screen
  [ ] "Get Started" navigates to Auth Screen
  [ ] Enter email → OTP is sent (check inbox / Supabase dashboard)
  [ ] Enter correct OTP → navigates to Personal Details
  [ ] Enter wrong OTP → shows error with shake animation
  [ ] Enter name + food preference → navigates to Home
  [ ] Kill app and reopen → goes directly to Home (session persists)

──────────────────────────────────────────────────────────────────
FLOW 2 — Recipe Creation
──────────────────────────────────────────────────────────────────
  [ ] Paste valid YouTube cooking video link on Home
  [ ] Tap create → navigates to creation screen with progress bar
  [ ] Progress labels cycle through readable messages
        (e.g. "Extracting audio…", "Transcribing…", "Building steps…")
  [ ] Wait for completion → navigates to Recipe page
  [ ] Recipe shows: title, creator name, cooking time, portion size
  [ ] Tap Ingredients → bottom sheet shows ingredient list with quantities
  [ ] Tap Preparation → bottom sheet shows prep step list
  [ ] Steps are listed as expandable cards, collapsed by default
  [ ] Expand a step → shows details, quantities, timer/flame info

──────────────────────────────────────────────────────────────────
FLOW 3 — Cooking Mode
──────────────────────────────────────────────────────────────────
  [ ] Tap "Start Cooking" → enters full-screen cooking mode
  [ ] Prep step shows "Done ✓" button — no timer visible
  [ ] Mark prep step done → card grays out with green tick, collapses
  [ ] Next step becomes active automatically
  [ ] Cooking step shows countdown timer + flame level indicator
  [ ] Timer counts down; plays sound + notification on completion
  [ ] Skip a step → marked skipped, advances to next
  [ ] Exit cooking mode mid-way → progress is saved
  [ ] Return to Home → active recipe bar shown at bottom
  [ ] Tap active recipe bar → resumes cooking at the saved step

──────────────────────────────────────────────────────────────────
FLOW 4 — Offline
──────────────────────────────────────────────────────────────────
  [ ] With a recipe already loaded, turn off device internet
  [ ] Open the recipe → loads from cache, no network error
  [ ] Enter cooking mode → all steps, timers work fully offline
  [ ] Offline banner appears (amber strip at top of screen)
  [ ] Notifications and timer sound fire correctly while offline
  [ ] Turn internet back on → banner disappears automatically

──────────────────────────────────────────────────────────────────
FLOW 5 — Edge Cases
──────────────────────────────────────────────────────────────────
  [ ] Paste invalid/random text → error: "link is broken or invalid"
  [ ] Paste a YouTube playlist URL → same error (not a video)
  [ ] Paste a timestamped link (e.g. ?t=60) → treated as the same video
  [ ] Paste same video link as an existing recipe → shows cached recipe
        immediately (no re-generation)
  [ ] Generate 6th recipe in one day → daily limit error shown
  [ ] No internet at home screen → offline banner appears
  [ ] No internet when tapping create → error screen with retry CTA

──────────────────────────────────────────────────────────────────
FLOW 6 — Profile
──────────────────────────────────────────────────────────────────
  [ ] Open Profile → shows name and email correctly
  [ ] Avatar shows initial letter when no photo is set
  [ ] "Add phone number" opens a bottom sheet, saves successfully
  [ ] My Creations lists all user recipes, newest first
  [ ] Load More loads the next page of 10 (if >10 recipes exist)
  [ ] Logout → confirm dialog appears
  [ ] Confirm logout → navigates to Welcome Screen
  [ ] After logout, deep-linking /home redirects to Welcome Screen

──────────────────────────────────────────────────────────────────
NOTES:
  Mark each [ ] with [x] as you verify.
  Log any failures with: screen, action taken, expected, actual.
──────────────────────────────────────────────────────────────────
''';

  print(lines);
}
