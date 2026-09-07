#!/bin/bash
# Point packages/koreader/VELBUILD at a nightly and refresh its checksums.
# Usage: ./scripts/bump-velbuild.sh <nightly-dir-name>
#   e.g. ./scripts/bump-velbuild.sh v2026.07.2-50-g7b0938bd8_2026-09-06
set -euo pipefail

nightly="${1:?usage: $0 <nightly-dir-name>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGE_DIR="$REPO_ROOT/packages/koreader"

base="${nightly#v}"; base="${base%%-*}"
count="${nightly#*-}"; count="${count%%-*}"
date="${nightly##*_}"; date="${date//-/}"
pkgver="${base}_git${date}_p${count}"

sed -i "s/^_nightly=.*/_nightly=$nightly/; s/^pkgver=.*/pkgver=$pkgver/; s/^pkgrel=.*/pkgrel=0/" \
    "$PACKAGE_DIR/VELBUILD"

command -v vbuild >/dev/null || { echo "vbuild not found" >&2; exit 1; }

work_dir=$(mktemp -d)
cp -r "$PACKAGE_DIR/." "$work_dir"
vbuild -C "$work_dir" checksum
cp "$work_dir/VELBUILD" "$PACKAGE_DIR/VELBUILD"
rm -rf "$work_dir"

echo "VELBUILD now at $nightly (pkgver=$pkgver)"
