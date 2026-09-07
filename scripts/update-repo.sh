#!/bin/bash
# Merge freshly built apks into the mirror repository and regenerate APKINDEX.
#
# Usage: ./scripts/update-repo.sh <ssh-user@host> <remote-dir> [keep]
#   Expects new apks in dist/<arch>/ and the signing key in keys/koreader-nightly.rsa.
#   For each arch: pull the existing apks from the mirror, add the new ones, keep
#   only the newest <keep> (default 10), rebuild + sign APKINDEX, push back.
set -euo pipefail

REMOTE="${1:?usage: $0 <ssh-user@host> <remote-dir> [keep]}"
REMOTE_DIR="${2:?usage: $0 <ssh-user@host> <remote-dir> [keep]}"
KEEP="${3:-10}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
KEY="$REPO_ROOT/keys/koreader-nightly.rsa"
IMAGE="${VBUILD_IMAGE:-ghcr.io/eeems/vbuild-builder:main}"

[ -f "$KEY" ] || { echo "Missing signing key $KEY" >&2; exit 1; }

ssh "$REMOTE" "mkdir -p '$REMOTE_DIR/aarch64' '$REMOTE_DIR/armv7'"

for arch in aarch64 armv7; do
    echo "==> $arch"
    mkdir -p "$REPO_ROOT/repo/$arch"
    rsync -a --include="*.apk" --exclude="*" "$REMOTE:$REMOTE_DIR/$arch/" "$REPO_ROOT/repo/$arch/"

    if ls "$REPO_ROOT/dist/$arch"/*.apk >/dev/null 2>&1; then
        cp "$REPO_ROOT/dist/$arch"/*.apk "$REPO_ROOT/repo/$arch/"
    fi

    # Drop everything but the newest $KEEP packages (by version order).
    ls "$REPO_ROOT/repo/$arch"/*.apk >/dev/null 2>&1 || { echo "no packages for $arch"; continue; }
    # Sort by mtime: rsync -a preserves it and freshly built apks are always newest.
    ls -t "$REPO_ROOT/repo/$arch"/*.apk | tail -n +$((KEEP + 1)) | while read -r old; do
        echo "pruning $(basename "$old")"
        rm -f "$old"
    done

    docker run --rm \
        -v "$REPO_ROOT/repo/$arch:/packages" \
        -v "$REPO_ROOT/keys:/keys:ro" \
        -w /packages \
        "$IMAGE" \
        sh -c "
            cp /keys/koreader-nightly.rsa.pub /etc/apk/keys/
            rm -f APKINDEX.tar.gz
            apk index --no-warnings --rewrite-arch $arch -o APKINDEX.tar.gz *.apk
            abuild-sign -k /keys/koreader-nightly.rsa APKINDEX.tar.gz
            apk verify *.apk
            chown $(id -u):$(id -g) APKINDEX.tar.gz
        "

    rsync -a --delete --include="*.apk" --include="APKINDEX.tar.gz" --exclude="*" \
        "$REPO_ROOT/repo/$arch/" "$REMOTE:$REMOTE_DIR/$arch/"
done

scp -q "$REPO_ROOT/keys/koreader-nightly.rsa.pub" "$REMOTE:$REMOTE_DIR/"
echo "Repository updated at $REMOTE:$REMOTE_DIR"
