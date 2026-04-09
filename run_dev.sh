#!/usr/bin/env bash
set -euo pipefail

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
[[ -z "${GEMINI_API_KEY:-}"    ]] && missing+=("GEMINI_API_KEY")

if [[ ${#missing[@]} -gt 0 ]]; then
  echo "Error: Missing environment variables in .env: ${missing[*]}"
  exit 1
fi

flutter run \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY" \
  --dart-define=GEMINI_API_KEY="$GEMINI_API_KEY" \
  "$@"
