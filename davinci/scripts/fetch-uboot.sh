#!/usr/bin/env bash
# Download + verify the pinned prebuilt Samsung U-Boot image.
# Usage: ./fetch-uboot.sh [output-dir]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/uboot.env"

OUT_DIR="${1:-$SCRIPT_DIR/images}"
mkdir -p "$OUT_DIR"
OUT="$OUT_DIR/boot-davinci-samsung.img"

echo "Downloading $UBOOT_ASSET ($UBOOT_TAG)..."
curl -fL --retry 3 -o "$OUT" "$UBOOT_URL"

echo "Verifying sha256..."
echo "$UBOOT_SHA256  $OUT" | sha256sum -c -

echo "Verifying size ($UBOOT_SIZE bytes)..."
actual=$(stat -c%s "$OUT")
if [ "$actual" != "$UBOOT_SIZE" ]; then
  echo "ERROR: size mismatch: got $actual, want $UBOOT_SIZE" >&2
  exit 1
fi

echo "OK: $OUT"
