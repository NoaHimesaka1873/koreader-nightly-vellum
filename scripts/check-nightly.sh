#!/bin/bash
# Find the newest KOReader nightly that has both reMarkable archives and compare it
# with the nightly currently recorded in packages/koreader/VELBUILD.
#
# Sources, in order:
#   1. https://build.koreader.rocks/download/nightly/ (the official nightly server)
#   2. GitLab CI artifacts of https://gitlab.com/koreader/nightly-builds, used
#      whenever the nightly server does not answer.
#
# Usage: ./scripts/check-nightly.sh [listing-html-file]
#   NIGHTLY=<dir name>   pin a nightly-server directory, e.g. 2026.07.2-351-g1294bb3
#   PIPELINE=<id>        pin a GitLab pipeline id instead of the newest one with reMarkable builds
#   listing-html-file    parse this saved nightly-server listing instead of fetching it
#                        (the per-nightly directories are still fetched)
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

# v2026.07.2-50-g7b0938bd8_2026-09-06 -> 2026.07.2_git20260906_p50
pkgver_of() {
    local base count date
    base="${1#v}"; base="${base%%-*}"
    count="${1#*-}"; count="${count%%-*}"
    date="${1##*_}"; date="${date//-/}"
    echo "${base}_git${date}_p${count}"
}

# Compare package versions, not names: the nightly server abbreviates the
# commit hash to 7 characters and GitLab to 9, so the same nightly carries a
# different name depending on where it came from. A pinned nightly or pipeline
# updates whenever it differs; otherwise only a newer nightly does, because the
# two sources are not always in sync (GitLab can be a day behind) and a fallback
# must never republish an older nightly over a newer one.
emit() {
    local pkgver cur update=false
    pkgver=$(pkgver_of "$latest")
    cur=$(pkgver_of "$current")
    if [ "$pkgver" != "$cur" ]; then
        if [ -n "${NIGHTLY:-}${PIPELINE:-}" ] \
            || [ "$(printf '%s\n%s\n' "$cur" "$pkgver" | sort -V | tail -1)" = "$pkgver" ]; then
            update=true
        else
            echo "Not updating: $latest is older than $current" >&2
        fi
    fi
    echo "current=$current"
    echo "latest=$latest"
    echo "pkgver=$pkgver"
    echo "update=$update"
    echo "origin=$origin"
    echo "aarch64_url=$aarch64_url"
    echo "armv7_url=$armv7_url"
}

# Look inside one nightly-server directory (e.g. 2026.07.2-351-g1294bb3/) for
# both reMarkable archives. The version with the build date is only in the file
# names: koreader-remarkable[-aarch64]-v2026.07.2-351-g1294bb3_2026-11-21.tar.xz.
# Older directories carried .zip files instead.
server_dir() {
    local dir="$1" listing file64 ver ext
    listing=$(curl -fsSL --retry 2 --max-time 60 "$NIGHTLY_BASE/$dir/") || return 1
    for ext in tar.xz zip; do
        file64=$(grep -oE "href=\"koreader-remarkable-aarch64-v[^\"/]*\.${ext//./\\.}\"" <<<"$listing" \
            | sed -E 's/^href="//; s/"$//' | head -1 || true)
        [ -n "$file64" ] || continue
        ver="${file64#koreader-remarkable-aarch64-}"; ver="${ver%."$ext"}"
        if grep -qF "href=\"koreader-remarkable-$ver.$ext\"" <<<"$listing"; then
            latest="$ver"
            aarch64_url="$NIGHTLY_BASE/$dir/$file64"
            armv7_url="$NIGHTLY_BASE/$dir/koreader-remarkable-$ver.$ext"
            origin="nightly-server"
            return 0
        fi
    done
    return 1
}

# Newest nightly-server directory with both reMarkable archives. Directory
# names look like 2026.07.2-351-g1294bb3/ (before the August 2026 outage they were
# v2026.07.2-50-g7b0938bd8_2026-09-06/).
from_server() {
    local listing candidates cand
    if [ -n "${1:-}" ]; then
        listing=$(cat "$1")
    else
        listing=$(curl -fsSL --max-time 60 "$NIGHTLY_BASE/") || return 1
    fi
    candidates=$(echo "$listing" \
        | grep -oE 'href="v?[0-9]+\.[0-9]+(\.[0-9]+)?-[0-9]+-g[0-9a-f]+(_[0-9]{4}-[0-9]{2}-[0-9]{2})?/"' \
        | sed -E 's/^href="//; s#/"$##' \
        | sort -u \
        | sed -E 's/^(v?)(.*)$/\2\t\1\2/' \
        | sort -t "$(printf '\t')" -k1,1Vr \
        | cut -f2)
    [ -n "$candidates" ] || return 1
    for cand in $candidates; do
        server_dir "$cand" && return 0
        echo "Skipping $cand: reMarkable archives not (yet) available" >&2
    done
    return 1
}

# Newest GitLab pipeline whose build_remarkable and build_remarkable_aarch64
# jobs both succeeded and still have their artifacts. The pipeline itself is
# not required to pass: since late October 2026 its Android jobs fail every
# day, which marks the whole pipeline failed while the reMarkable builds are fine.
from_gitlab() {
    local pipelines pid jobs job64 job32 file64 file32 ver
    if [ -n "${1:-}" ]; then
        pipelines="$1"
    else
        pipelines=$(curl -fsSL --retry 3 "$GITLAB_API/pipelines?ref=master&per_page=10" | jq -r '.[].id')
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
    server_dir "${NIGHTLY%/}" || { echo "No reMarkable archives in nightly-server directory $NIGHTLY" >&2; exit 1; }
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
