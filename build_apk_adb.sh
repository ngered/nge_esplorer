#!/usr/bin/env bash
# Build de l'APK en local et installation sur un smartphone via ADB.
# Usage :
#   ./build_apk_adb.sh                 # debug + install + launch
#   BUILD=release ./build_apk_adb.sh   # release
#   NO_LAUNCH=1 ./build_apk_adb.sh     # pas de am start
#   NO_INSTALL=1 ./build_apk_adb.sh    # build seul
#   DEVICE=<serial> ./build_apk_adb.sh # cible un device adb precis

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

BUILD="${BUILD:-debug}"            # debug | profile | release
PACKAGE_ID="${PACKAGE_ID:-fr.nge.esplorer}"
MAIN_ACTIVITY="${MAIN_ACTIVITY:-.MainActivity}"
ADB="${ADB:-adb}"
FLUTTER="${FLUTTER:-flutter}"

ENV_FILE="$SCRIPT_DIR/.env"
DART_DEFINES=()
if [[ -f "$ENV_FILE" ]]; then
  # shellcheck disable=SC1090
  source "$ENV_FILE"
  [[ -n "${SUPABASE_URL:-}" ]]      && DART_DEFINES+=(--dart-define=SUPABASE_URL="$SUPABASE_URL")
  [[ -n "${SUPABASE_ANON_KEY:-}" ]] && DART_DEFINES+=(--dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY")
fi

case "$BUILD" in
  debug)   APK="build/app/outputs/flutter-apk/app-debug.apk"   ;;
  profile) APK="build/app/outputs/flutter-apk/app-profile.apk" ;;
  release) APK="build/app/outputs/flutter-apk/app-release.apk" ;;
  *) echo "BUILD inconnu: $BUILD (debug|profile|release)" >&2; exit 1 ;;
esac

echo "==> flutter pub get"
"$FLUTTER" pub get

echo "==> flutter build apk --$BUILD"
"$FLUTTER" build apk "--$BUILD" "${DART_DEFINES[@]}"

if [[ ! -f "$APK" ]]; then
  echo "APK introuvable: $APK" >&2
  exit 1
fi
echo "==> APK: $APK ($(du -h "$APK" | cut -f1))"

if [[ "${NO_INSTALL:-0}" == "1" ]]; then
  echo "==> NO_INSTALL=1, fin."
  exit 0
fi

ADB_ARGS=()
if [[ -n "${DEVICE:-}" ]]; then
  ADB_ARGS=(-s "$DEVICE")
fi

echo "==> Devices ADB :"
"$ADB" devices

ONLINE_COUNT=$("$ADB" devices | awk 'NR>1 && $2=="device"{c++} END{print c+0}')
if [[ "$ONLINE_COUNT" -eq 0 ]]; then
  echo "Aucun smartphone detecte via ADB. Branche le telephone (debogage USB active)." >&2
  exit 2
fi

echo "==> Installation sur le device..."
"$ADB" "${ADB_ARGS[@]}" install -r "$APK"

if [[ "${NO_LAUNCH:-0}" != "1" ]]; then
  echo "==> Lancement de $PACKAGE_ID/$MAIN_ACTIVITY"
  "$ADB" "${ADB_ARGS[@]}" shell am start -n "${PACKAGE_ID}/${MAIN_ACTIVITY}"
fi

echo "==> Done."
