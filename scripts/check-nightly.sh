#!/bin/bash
# Find the newest KOReader nightly that has both reMarkable zips and compare it
# with the nightly currently recorded in packages/koreader/VELBUILD.
#
# Usage: [NIGHTLY=<dir name>] ./scripts/check-nightly.sh [listing-html-file]
#   NIGHTLY pins a specific nightly directory name instead of consulting the listing.
#   A listing file skips the network entirely (used for testing).
# Prints KEY=VALUE lines: current, latest, pkgver, update (true/false).
set -euo pipefail

NIGHTLY_BASE="${NIGHTLY_BASE:-https://build.koreader.rocks/download/nightly}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VELBUILD="$(dirname "$SCRIPT_DIR")/packages/koreader/VELBUILD"

current=$(sed -n 's/^_nightly=//p' "$VELBUILD")

emit() {
    # v2026.07.2-50-g7b0938bd8_2026-09-06 -> 2026.07.2_git20260906_p50
    local latest="$1" base count date
    base="${latest#v}"; base="${base%%-*}"
    count="${latest#*-}"; count="${count%%-*}"
    date="${latest##*_}"; date="${date//-/}"
    echo "current=$current"
    echo "latest=$latest"
    echo "pkgver=${base}_git${date}_p${count}"
    if [ "$latest" != "$current" ]; then echo "update=true"; else echo "update=false"; fi
}

if [ -n "${NIGHTLY:-}" ]; then
    emit "$NIGHTLY"
    exit 0
fi

if [ -n "${1:-}" ]; then
    listing=$(cat "$1")
else
    listing=$(curl -fsSL --retry 3 --retry-delay 20 "$NIGHTLY_BASE/")
fi

# Directory names look like v2026.07.2-50-g7b0938bd8_2026-09-06/.
# Order by build date, then by commit count, newest first.
candidates=$(echo "$listing" \
    | grep -oE 'href="v[0-9]+\.[0-9]+(\.[0-9]+)?-[0-9]+-g[0-9a-f]+_[0-9]{4}-[0-9]{2}-[0-9]{2}/"' \
    | sed -E 's/^href="//; s#/"$##' \
    | sort -u \
    | sed -E 's/^(v[^-]+-([0-9]+)-g[0-9a-f]+_([0-9-]+))$/\3\t\2\t\1/' \
    | sort -k1,1r -k2,2nr \
    | cut -f3)

if [ -z "$candidates" ]; then
    echo "No nightly directories found in listing" >&2
    exit 1
fi

latest=""
if [ -n "${1:-}" ]; then
    latest=$(echo "$candidates" | head -1)
else
    # A nightly may still be uploading; use the newest one whose reMarkable zips both exist.
    for cand in $candidates; do
        if curl -fsSIL --retry 2 "$NIGHTLY_BASE/$cand/koreader-remarkable-aarch64-$cand.zip" >/dev/null \
            && curl -fsSIL --retry 2 "$NIGHTLY_BASE/$cand/koreader-remarkable-$cand.zip" >/dev/null; then
            latest="$cand"
            break
        fi
        echo "Skipping $cand: reMarkable zips not (yet) available" >&2
    done
fi

if [ -z "$latest" ]; then
    echo "No nightly with reMarkable builds found" >&2
    exit 1
fi

emit "$latest"
