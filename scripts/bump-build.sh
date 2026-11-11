#!/bin/sh
set -eu

PLIST="$(dirname "$0")/../Chet/Info.plist"
current=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$PLIST")
case "$current" in
  ''|*[!0-9]*) printf 'CFBundleVersion is not a number: %s\n' "$current" >&2; exit 1 ;;
esac
next=$((current + 1))
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $next" "$PLIST"
printf 'build %s -> %s\n' "$current" "$next"
