#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ENV_FILE="$SCRIPT_DIR/.env"
DART_DEFINES=()
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  [[ -n "${SUPABASE_URL:-}" ]]      && DART_DEFINES+=(--dart-define=SUPABASE_URL="$SUPABASE_URL")
  [[ -n "${SUPABASE_ANON_KEY:-}" ]] && DART_DEFINES+=(--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY")
fi

MODE="${MODE:-run}"   # run | release | profile
case "$MODE" in
  run)
    exec flutter run -d linux "${DART_DEFINES[@]}" "$@"
    ;;
  release|profile|debug)
    flutter build linux "--$MODE" "${DART_DEFINES[@]}"
    BIN="$SCRIPT_DIR/build/linux/x64/$MODE/bundle/nge_esplorer"
    echo "==> Lancement de $BIN"
    exec "$BIN" "$@"
    ;;
  *)
    echo "MODE inconnu: $MODE (valeurs: run|debug|profile|release)" >&2
    exit 1
    ;;
esac
