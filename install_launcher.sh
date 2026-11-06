#!/usr/bin/env bash
# Installe le raccourci menu Linux (XDG) pour NgeEsPlorer.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DESKTOP_SRC="$SCRIPT_DIR/nge_esplorer.desktop"
DEST_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
DEST="$DEST_DIR/nge_esplorer.desktop"

mkdir -p "$DEST_DIR"
install -m 0644 "$DESKTOP_SRC" "$DEST"

if command -v update-desktop-database >/dev/null 2>&1; then
  update-desktop-database "$DEST_DIR" || true
fi

echo "==> Raccourci installe : $DEST"
echo "    (Lance 'NgeEsPlorer' depuis le menu de ton bureau)"
