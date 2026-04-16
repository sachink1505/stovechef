#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────
# StoveChef — Production Build Script
# ──────────────────────────────────────────────────────────────
# Usage:
#   ./build_release.sh apk        # Android APK
#   ./build_release.sh appbundle   # Android App Bundle (for Play Store)
#   ./build_release.sh ios         # iOS build (requires Xcode)
# ──────────────────────────────────────────────────────────────

# Source environment variables from .env
if [[ ! -f .env ]]; then
  echo "Error: .env file not found. Copy .env.example and fill in your keys."
  exit 1
fi

set -a && source .env && set +a

# Validate keys are present
missing=()
[[ -z "${SUPABASE_URL:-}"      ]] && missing+=("SUPABASE_URL")
[[ -z "${SUPABASE_ANON_KEY:-}" ]] && missing+=("SUPABASE_ANON_KEY")

LLM_PROVIDER="${LLM_PROVIDER:-gemini}"
if [[ "$LLM_PROVIDER" == "openai" ]]; then
  [[ -z "${OPENAI_API_KEY:-}" ]] && missing+=("OPENAI_API_KEY")
else
  [[ -z "${GEMINI_API_KEY:-}" ]] && missing+=("GEMINI_API_KEY")
fi

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: Missing environment variables in .env: ${missing[*]}"
  exit 1
fi

DART_DEFINES=(
  --dart-define=SUPABASE_URL="$SUPABASE_URL"
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
  --dart-define=GEMINI_API_KEY="${GEMINI_API_KEY:-}"
  --dart-define=LLM_PROVIDER="$LLM_PROVIDER"
  --dart-define=OPENAI_API_KEY="${OPENAI_API_KEY:-}"
  --dart-define=OPENAI_MODEL="${OPENAI_MODEL:-gpt-4o-mini}"
)

BUILD_TYPE="${1:-apk}"

echo "🔨 Building StoveChef ($BUILD_TYPE) ..."
echo ""

case "$BUILD_TYPE" in
  apk)
    flutter build apk --release "${DART_DEFINES[@]}"
    echo ""
    echo "✅ APK built: build/app/outputs/flutter-apk/app-release.apk"
    ;;
  appbundle)
    flutter build appbundle --release "${DART_DEFINES[@]}"
    echo ""
    echo "✅ App Bundle built: build/app/outputs/bundle/release/app-release.aab"
    ;;
  ios)
    flutter build ios --release "${DART_DEFINES[@]}"
    echo ""
    echo "✅ iOS build complete. Open ios/Runner.xcworkspace in Xcode to archive."
    ;;
  *)
    echo "Usage: ./build_release.sh [apk|appbundle|ios]"
    exit 1
    ;;
esac
