#!/bin/bash
# Point packages/koreader/VELBUILD at a nightly and refresh its checksums.
#
# Usage: ./scripts/bump-velbuild.sh <nightly> <aarch64-zip-url> <armv7-zip-url>
#   e.g. ./scripts/bump-velbuild.sh v2026.07.2-50-g7b0938bd8_2026-09-06 \
#            https://build.koreader.rocks/download/nightly/v2026.07.2-50-g7b0938bd8_2026-09-06/koreader-remarkable-aarch64-v2026.07.2-50-g7b0938bd8_2026-09-06.zip \
#            https://build.koreader.rocks/download/nightly/v2026.07.2-50-g7b0938bd8_2026-09-06/koreader-remarkable-v2026.07.2-50-g7b0938bd8_2026-09-06.zip
#   The URLs are what scripts/check-nightly.sh prints as aarch64_url and armv7_url.
set -euo pipefail

usage="usage: $0 <nightly> <aarch64-zip-url> <armv7-zip-url>"
nightly="${1:?$usage}"
aarch64_url="${2:?$usage}"
armv7_url="${3:?$usage}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGE_DIR="$REPO_ROOT/packages/koreader"

base="${nightly#v}"; base="${base%%-*}"
count="${nightly#*-}"; count="${count%%-*}"
date="${nightly##*_}"; date="${date//-/}"
pkgver="${base}_git${date}_p${count}"

# Escape for use in a sed replacement with | as the delimiter.
esc() { printf '%s' "$1" | sed 's/[&|\\]/\\&/g'; }

sed -i \
    -e "s|^_nightly=.*|_nightly=$(esc "$nightly")|" \
    -e "s|^_aarch64_url=.*|_aarch64_url=\"$(esc "$aarch64_url")\"|" \
    -e "s|^_armv7_url=.*|_armv7_url=\"$(esc "$armv7_url")\"|" \
    -e "s|^pkgver=.*|pkgver=$pkgver|" \
    -e "s|^pkgrel=.*|pkgrel=0|" \
    "$PACKAGE_DIR/VELBUILD"

command -v vbuild >/dev/null || { echo "vbuild not found" >&2; exit 1; }

work_dir=$(mktemp -d)
cp -r "$PACKAGE_DIR/." "$work_dir"
vbuild -C "$work_dir" checksum
cp "$work_dir/VELBUILD" "$PACKAGE_DIR/VELBUILD"
rm -rf "$work_dir"

echo "VELBUILD now at $nightly (pkgver=$pkgver)"
