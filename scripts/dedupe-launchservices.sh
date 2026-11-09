#!/usr/bin/env bash
# Keep exactly ONE chet registration in LaunchServices: the app we just built.
#
# Why: macOS relaunches an app *by bundle identifier* when a Full Disk Access grant is
# toggled. With stale copies registered (old worktrees, /tmp builds, Release), the
# relaunched process can be a different copy than the one the user granted — which is why
# Full Disk Access appeared to need granting twice.
set -euo pipefail
KEEP="${1:?usage: dedupe-launchservices.sh <path-to-chet.app>}"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
KEEP_ABS="$(cd "$(dirname "$KEEP")" && pwd)/$(basename "$KEEP")"

"$LSREGISTER" -dump 2>/dev/null \
  | grep -oE '/[^ ]*chet\.app' \
  | sort -u \
  | while read -r path; do
      [ "$path" = "$KEEP_ABS" ] && continue
      "$LSREGISTER" -u "$path" 2>/dev/null || true
      echo "unregistered stale copy: $path"
    done

"$LSREGISTER" -f "$KEEP_ABS" 2>/dev/null || true
echo "canonical copy: $KEEP_ABS"
