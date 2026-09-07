#!/bin/bash
# Find the newest KOReader nightly that has both reMarkable zips and compare it
# with the nightly currently recorded in packages/koreader/VELBUILD.
#
# Sources, in order:
#   1. https://build.koreader.rocks/download/nightly/ (the official nightly server)
#   2. GitLab CI artifacts of https://gitlab.com/koreader/nightly-builds, used
#      whenever the nightly server does not answer.
#
# Usage: ./scripts/check-nightly.sh [listing-html-file]
#   NIGHTLY=<dir name>   pin a nightly-server directory, e.g. v2026.07.2-50-g7b0938bd8_2026-09-06
#   PIPELINE=<id>        pin a GitLab pipeline id instead of the newest successful one
#   listing-html-file    parse this saved nightly-server listing (offline testing)
#
# Prints KEY=VALUE lines: current, latest, pkgver, update, origin, aarch64_url, armv7_url.
set -euo pipefail

NIGHTLY_BASE="${NIGHTLY_BASE:-https://build.koreader.rocks/download/nightly}"
GITLAB_API="${GITLAB_API:-https://gitlab.com/api/v4/projects/koreader%2Fnightly-builds}"
GITLAB_WEB="${GITLAB_WEB:-https://gitlab.com/koreader/nightly-builds}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VELBUILD="$(dirname "$SCRIPT_DIR")/packages/koreader/VELBUILD"

current=$(sed -n 's/^_nightly=//p' "$VELBUILD")
latest="" aarch64_url="" armv7_url="" origin=""

emit() {
    # v2026.07.2-50-g7b0938bd8_2026-09-06 -> 2026.07.2_git20260906_p50
    local base count date
    base="${latest#v}"; base="${base%%-*}"
    count="${latest#*-}"; count="${count%%-*}"
    date="${latest##*_}"; date="${date//-/}"
    echo "current=$current"
    echo "latest=$latest"
    echo "pkgver=${base}_git${date}_p${count}"
    if [ "$latest" != "$current" ]; then echo "update=true"; else echo "update=false"; fi
    echo "origin=$origin"
    echo "aarch64_url=$aarch64_url"
    echo "armv7_url=$armv7_url"
}

server_urls() {
    aarch64_url="$NIGHTLY_BASE/$1/koreader-remarkable-aarch64-$1.zip"
    armv7_url="$NIGHTLY_BASE/$1/koreader-remarkable-$1.zip"
}

# Newest nightly-server directory whose two reMarkable zips both exist.
# Directory names look like v2026.07.2-50-g7b0938bd8_2026-09-06/.
from_server() {
    local listing candidates cand
    if [ -n "${1:-}" ]; then
        listing=$(cat "$1")
    else
        listing=$(curl -fsSL --max-time 60 "$NIGHTLY_BASE/") || return 1
    fi
    candidates=$(echo "$listing" \
        | grep -oE 'href="v[0-9]+\.[0-9]+(\.[0-9]+)?-[0-9]+-g[0-9a-f]+_[0-9]{4}-[0-9]{2}-[0-9]{2}/"' \
        | sed -E 's/^href="//; s#/"$##' \
        | sort -u \
        | sed -E 's/^(v[^-]+-([0-9]+)-g[0-9a-f]+_([0-9-]+))$/\3\t\2\t\1/' \
        | sort -k1,1r -k2,2nr \
        | cut -f3)
    [ -n "$candidates" ] || return 1
    for cand in $candidates; do
        if [ -n "${1:-}" ] \
            || { curl -fsSIL --retry 2 "$NIGHTLY_BASE/$cand/koreader-remarkable-aarch64-$cand.zip" >/dev/null \
                 && curl -fsSIL --retry 2 "$NIGHTLY_BASE/$cand/koreader-remarkable-$cand.zip" >/dev/null; }; then
            latest="$cand"
            server_urls "$cand"
            origin="nightly-server"
            return 0
        fi
        echo "Skipping $cand: reMarkable zips not (yet) available" >&2
    done
    return 1
}

# Newest successful GitLab pipeline whose build_remarkable and
# build_remarkable_aarch64 jobs both still have their artifacts.
from_gitlab() {
    local pipelines pid jobs job64 job32 file64 file32 ver
    if [ -n "${1:-}" ]; then
        pipelines="$1"
    else
        pipelines=$(curl -fsSL --retry 3 "$GITLAB_API/pipelines?ref=master&status=success&per_page=10" | jq -r '.[].id')
    fi
    for pid in $pipelines; do
        jobs=$(curl -fsSL --retry 3 "$GITLAB_API/pipelines/$pid/jobs?per_page=100")
        job64=$(echo "$jobs" | jq -r '[.[] | select(.name == "build_remarkable_aarch64" and .status == "success")][0].id // empty')
        job32=$(echo "$jobs" | jq -r '[.[] | select(.name == "build_remarkable" and .status == "success")][0].id // empty')
        if [ -z "$job64" ] || [ -z "$job32" ]; then
            echo "Skipping pipeline $pid: reMarkable jobs missing or failed" >&2
            continue
        fi
        file64=$(curl -fsSL --retry 3 "$GITLAB_WEB/-/jobs/$job64/artifacts/browse/koreader/" \
            | grep -oE 'koreader-remarkable-aarch64-v[^"<> ]*\.zip' | head -1 || true)
        if [ -z "$file64" ]; then
            echo "Skipping pipeline $pid: aarch64 artifact not listed (expired?)" >&2
            continue
        fi
        ver="${file64#koreader-remarkable-aarch64-}"; ver="${ver%.zip}"
        file32="koreader-remarkable-$ver.zip"
        if ! curl -fsSL --retry 3 "$GITLAB_WEB/-/jobs/$job32/artifacts/browse/koreader/" | grep -qF "$file32"; then
            echo "Skipping pipeline $pid: $file32 not listed in job $job32" >&2
            continue
        fi
        latest="$ver"
        aarch64_url="$GITLAB_API/jobs/$job64/artifacts/koreader/$file64"
        armv7_url="$GITLAB_API/jobs/$job32/artifacts/koreader/$file32"
        origin="gitlab"
        return 0
    done
    return 1
}

if [ -n "${NIGHTLY:-}" ]; then
    latest="$NIGHTLY"; server_urls "$NIGHTLY"; origin="nightly-server"
elif [ -n "${PIPELINE:-}" ]; then
    from_gitlab "$PIPELINE" || { echo "Pipeline $PIPELINE has no usable reMarkable artifacts" >&2; exit 1; }
elif [ -n "${1:-}" ]; then
    from_server "$1" || { echo "No nightly with reMarkable builds in $1" >&2; exit 1; }
else
    if ! from_server; then
        echo "Nightly server unavailable or empty, falling back to GitLab CI artifacts" >&2
        from_gitlab || { echo "No usable nightly found on either source" >&2; exit 1; }
    fi
fi

emit
