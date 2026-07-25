#!/usr/bin/env bash
# Builds a release zip of the mod into dist/release/.
# The zip contains PalStorageManager/ ready to drop into
# <GamePass>/Pal/Binaries/WinGDK/ue4ss/Mods/  (or WinGDK/Mods/).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SRC="$REPO_ROOT/src/PalStorageManager"
OUT_DIR="$REPO_ROOT/dist/release"
VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$SRC/mod.json" | head -1)"

if [[ -z "$VERSION" ]]; then
  echo "error: could not read version from mod.json" >&2
  exit 1
fi

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$STAGE/PalStorageManager"
cp -R "$SRC/Scripts" "$STAGE/PalStorageManager/"
cp -R "$SRC/config" "$STAGE/PalStorageManager/" 2>/dev/null || true
cp "$SRC/enabled.txt" "$SRC/mod.json" "$STAGE/PalStorageManager/"
# Strip local dev overrides and macOS noise.
rm -f "$STAGE/PalStorageManager/Scripts/config/user.lua"
find "$STAGE" -name ".DS_Store" -delete -o -name ".gitkeep" -delete

mkdir -p "$OUT_DIR"
ZIP="$OUT_DIR/PalStorageManager-v$VERSION.zip"
rm -f "$ZIP"
(cd "$STAGE" && zip -qr "$ZIP" PalStorageManager)

echo "built: $ZIP"
unzip -l "$ZIP"
