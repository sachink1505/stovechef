#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# StoveChef — Release Build Script
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

print_step()  { echo -e "\n${CYAN}${BOLD}▶ $1${RESET}"; }
print_ok()    { echo -e "${GREEN}✔ $1${RESET}"; }
print_warn()  { echo -e "${YELLOW}⚠ $1${RESET}"; }
print_error() { echo -e "${RED}✖ $1${RESET}"; }

# ─── Environment variable check ───────────────────────────────────────────────

echo -e "\n${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║        StoveChef Release Build Script            ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}"

echo -e "
${BOLD}REQUIRED ENVIRONMENT VARIABLES${RESET}
Set these before running the script:

  export SUPABASE_URL=https://xxxxxxxxxxxx.supabase.co
  export SUPABASE_ANON_KEY=eyJ...
  export GEMINI_API_KEY=AIzaSy...

Or source them from a .env file:

  set -a && source .env && set +a && ./build.sh
"

# Validate all three are set and non-empty.
missing=()
[[ -z "${SUPABASE_URL:-}"      ]] && missing+=("SUPABASE_URL")
[[ -z "${SUPABASE_ANON_KEY:-}" ]] && missing+=("SUPABASE_ANON_KEY")
[[ -z "${GEMINI_API_KEY:-}"    ]] && missing+=("GEMINI_API_KEY")

if [[ ${#missing[@]} -gt 0 ]]; then
  print_error "Missing required environment variables:"
  for var in "${missing[@]}"; do
    echo -e "  ${RED}• $var${RESET}"
  done
  echo ""
  exit 1
fi

print_ok "All environment variables are set."

# ─── Optional: select targets ─────────────────────────────────────────────────
# By default, build both APK and AAB. Pass --apk-only or --aab-only to override.

BUILD_APK=true
BUILD_AAB=true

for arg in "$@"; do
  case "$arg" in
    --apk-only) BUILD_AAB=false ;;
    --aab-only) BUILD_APK=false ;;
    --help|-h)
      echo "Usage: ./build.sh [--apk-only | --aab-only]"
      exit 0
      ;;
  esac
done

DART_DEFINES=(
  "--dart-define=SUPABASE_URL=$SUPABASE_URL"
  "--dart-define=SUPABASE_ANON_KEY=$SUPABASE_ANON_KEY"
  "--dart-define=GEMINI_API_KEY=$GEMINI_API_KEY"
)

# ─── 1. Clean ─────────────────────────────────────────────────────────────────

print_step "Running flutter clean..."
flutter clean
print_ok "Clean complete."

# ─── 2. Get dependencies ──────────────────────────────────────────────────────

print_step "Getting dependencies..."
flutter pub get
print_ok "Dependencies resolved."

# ─── 3. Android APK ──────────────────────────────────────────────────────────

if [[ "$BUILD_APK" == true ]]; then
  print_step "Building Android APK (release)..."
  flutter build apk --release "${DART_DEFINES[@]}"
  APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
  if [[ -f "$APK_PATH" ]]; then
    APK_SIZE=$(du -sh "$APK_PATH" | cut -f1)
    print_ok "APK built: $APK_PATH ($APK_SIZE)"
  else
    print_warn "APK build completed but file not found at expected path."
  fi
fi

# ─── 4. Android App Bundle ───────────────────────────────────────────────────

if [[ "$BUILD_AAB" == true ]]; then
  print_step "Building Android App Bundle (release)..."
  flutter build appbundle --release "${DART_DEFINES[@]}"
  AAB_PATH="build/app/outputs/bundle/release/app-release.aab"
  if [[ -f "$AAB_PATH" ]]; then
    AAB_SIZE=$(du -sh "$AAB_PATH" | cut -f1)
    print_ok "AAB built: $AAB_PATH ($AAB_SIZE)"
  else
    print_warn "AAB build completed but file not found at expected path."
  fi
fi

# ─── 5. Summary ───────────────────────────────────────────────────────────────

echo -e "\n${BOLD}╔══════════════════════════════════════════════════╗${RESET}"
echo -e "${BOLD}║                 Build Summary                    ║${RESET}"
echo -e "${BOLD}╚══════════════════════════════════════════════════╝${RESET}\n"

if [[ "$BUILD_APK" == true ]]; then
  echo -e "  ${GREEN}APK${RESET}  build/app/outputs/flutter-apk/app-release.apk"
fi
if [[ "$BUILD_AAB" == true ]]; then
  echo -e "  ${GREEN}AAB${RESET}  build/app/outputs/bundle/release/app-release.aab"
fi

echo -e "
${BOLD}NEXT STEPS${RESET}

  ${YELLOW}▸ Play Store:${RESET}  upload build/app/outputs/bundle/release/app-release.aab
  ${YELLOW}▸ Testing:${RESET}     install build/app/outputs/flutter-apk/app-release.apk
  ${YELLOW}▸ iOS:${RESET}         open ios/Runner.xcworkspace in Xcode, set your team, and archive.
  ${YELLOW}▸ TestFlight:${RESET}  after archiving in Xcode, upload via Xcode Organizer.

  See DEPLOYMENT.md for full step-by-step instructions.
"
