#!/bin/bash
# Build packages/koreader for one architecture with vbuild into dist/<arch>/.
# Usage: ./scripts/build-package.sh <aarch64|armv7>
#
# Signs with keys/koreader-nightly.rsa if present, otherwise with a throwaway
# dev key in keys/koreader-nightly-dev.rsa. Requires docker or podman.
set -euo pipefail

ARCH="${1:?usage: $0 <aarch64|armv7>}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
PACKAGE_DIR="$REPO_ROOT/packages/koreader"

command -v vbuild >/dev/null || { echo "vbuild not found" >&2; exit 1; }

if [ -f "$REPO_ROOT/keys/koreader-nightly.rsa" ]; then
    KEY_NAME=koreader-nightly
else
    KEY_NAME=koreader-nightly-dev
    if [ ! -f "$REPO_ROOT/keys/$KEY_NAME.rsa" ]; then
        echo "Generating $KEY_NAME signing keypair for build testing..."
        openssl genrsa -out "$REPO_ROOT/keys/$KEY_NAME.rsa" 4096 2>/dev/null
        openssl rsa -in "$REPO_ROOT/keys/$KEY_NAME.rsa" -pubout -out "$REPO_ROOT/keys/$KEY_NAME.rsa.pub" 2>/dev/null
        chmod 600 "$REPO_ROOT/keys/$KEY_NAME.rsa"
    fi
fi
mkdir -p ~/.config/vbuild
cp "$REPO_ROOT/keys/$KEY_NAME.rsa" ~/.config/vbuild/"$KEY_NAME".rsa
cp "$REPO_ROOT/keys/$KEY_NAME.rsa.pub" ~/.config/vbuild/"$KEY_NAME".rsa.pub

# Reproducible timestamp: the nightly build date recorded in the VELBUILD.
nightly=$(sed -n "s/^_nightly=//p" "$PACKAGE_DIR/VELBUILD")
SOURCE_DATE_EPOCH=$(date -u -d "${nightly##*_}" +%s 2>/dev/null || date +%s)

mkdir -p "$REPO_ROOT/dist/$ARCH"
work_dir=$(mktemp -d)
cp -r "$PACKAGE_DIR/." "$work_dir"
SOURCE_DATE_EPOCH=$SOURCE_DATE_EPOCH VBUILD_KEY_NAME=$KEY_NAME CARCH=$ARCH vbuild -C "$work_dir" all
cp -r "$work_dir/dist/." "$REPO_ROOT/dist/"
vbuild -C "$work_dir" clean
rm -rf "$work_dir"

ls -la "$REPO_ROOT/dist/$ARCH"/*.apk
