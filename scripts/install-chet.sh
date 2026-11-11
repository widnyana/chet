#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Install the latest published Chet release on this Mac.

Usage: bash scripts/install-chet.sh [options]

Options:
  --tag TAG        Install a specific release tag (default: latest)
  --target DIR     Install into DIR (default: /Applications)
  --user           Install into ~/Applications
  --dry-run        Print the tag, asset, URL, target, and steps; write nothing
  --archive FILE   Install a local .dmg or .zip instead of downloading
  --help           Show this help and exit

Environment:
  CHET_RELEASE_JSON   Read release metadata from a local file
  GITHUB_TOKEN        Sent as one Authorization header when set

Exit codes:
  0  installed
  2  no published release
  3  no usable .dmg or .zip asset
  4  download or integrity check failed
  5  Chet is running
  6  target is not writable
  7  verification, install, or quarantine failure
  8  usage error

Examples:
  mise run install-chet
  mise run install-chet -- --user
  mise run install-chet -- --tag v0.10.0 --target /tmp/chet
EOF
}

tag_arg=""
target_arg=""
use_user=0
dry_run=0
archive=""

while [ $# -gt 0 ]; do
  case "$1" in
    --tag)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        printf 'Missing value for --tag.\n' >&2
        usage >&2
        exit 8
      fi
      tag_arg=$2
      shift 2
      ;;
    --target)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        printf 'Missing value for --target.\n' >&2
        usage >&2
        exit 8
      fi
      target_arg=$2
      shift 2
      ;;
    --user)
      use_user=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --archive)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        printf 'Missing value for --archive.\n' >&2
        usage >&2
        exit 8
      fi
      archive=$2
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      usage >&2
      exit 8
      ;;
  esac
done

releases_url="https://github.com/widnyana/chet/releases"
api_base="https://api.github.com/repos/widnyana/chet/releases"
bundle_id="id.web.widnyana.chet"

if [ -n "$target_arg" ]; then
  target=$target_arg
elif [ "$use_user" = 1 ]; then
  target="$HOME/Applications"
else
  target="/Applications"
fi

tmp=""
mounted=0
mount_point=""

cleanup() {
  if [ "$mounted" = 1 ] && [ -n "$mount_point" ]; then
    hdiutil detach "$mount_point" >/dev/null 2>&1 || hdiutil detach "$mount_point" -force >/dev/null 2>&1 || true
    mounted=0
  fi
  if [ -n "$tmp" ] && [ -d "$tmp" ]; then
    rm -rf "$tmp"
  fi
}

trap 'exit 130' INT
trap 'exit 143' TERM
trap 'status=$?; cleanup; exit "$status"' EXIT

read_release() {
  python3 - "$1" "$2" <<'PYCODE'
import json
import sys

path = sys.argv[1]
mode = sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as handle:
        data = json.load(handle)
except Exception:
    data = {}
if not isinstance(data, dict):
    data = {}
assets = [asset for asset in (data.get("assets") or []) if isinstance(asset, dict)]

if mode == "tag":
    print(data.get("tag_name") or "")
elif mode == "names":
    for asset in assets:
        print(asset.get("name") or "")
elif mode == "asset":
    def name_of(asset):
        return str(asset.get("name") or "").lower()

    rules = [
        lambda name: name.endswith(".dmg") and "chet" in name,
        lambda name: name.endswith(".dmg"),
        lambda name: name.endswith(".zip") and "chet" in name,
        lambda name: name.endswith(".zip"),
    ]
    for rule in rules:
        for asset in assets:
            if rule(name_of(asset)):
                print("%s\t%s\t%s" % (
                    asset.get("name"),
                    asset.get("browser_download_url") or "",
                    asset.get("url") or "",
                ))
                sys.exit(0)
    sys.exit(1)
PYCODE
}

tmp=$(mktemp -d "${TMPDIR:-/tmp}/chet-install.XXXXXX")

curl_args=(-sSL -H 'Accept: application/vnd.github+json')
if [ -n "${GITHUB_TOKEN:-}" ]; then
  curl_args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
fi

json_file=""
if [ -n "$archive" ]; then
  release_tag=${tag_arg:-local}
else
  if [ -n "${CHET_RELEASE_JSON:-}" ]; then
    json_file=$CHET_RELEASE_JSON
    if [ ! -r "$json_file" ]; then
      printf 'Cannot read release metadata: %s\n' "$json_file" >&2
      printf 'Releases: %s\n' "$releases_url" >&2
      exit 2
    fi
  else
    json_file="$tmp/release.json"
    api_url="$api_base/latest"
    if [ -n "$tag_arg" ]; then
      api_url="$api_base/tags/$tag_arg"
    fi
    status=$(curl "${curl_args[@]}" -o "$json_file" -w '%{http_code}' "$api_url" || true)
    case "$status" in
      200|201) ;;
      404)
        if [ -n "${GITHUB_TOKEN:-}" ]; then
          printf 'The release API answered 404 for the token in GITHUB_TOKEN.\n' >&2
          printf 'A private repository needs a token with repo access, or gh auth without that variable.\n' >&2
          printf 'Try: GITHUB_TOKEN=$(env -u GITHUB_TOKEN gh auth token) bash %s\n' "$0" >&2
          printf 'Or install a local build: bash %s --archive dist/chet.zip\n' "$0" >&2
        else
          printf 'No published release yet.\n' >&2
        fi
        printf 'Releases: %s\n' "$releases_url" >&2
        exit 2
        ;;
      *)
        printf 'The release API returned HTTP %s.\n' "$status" >&2
        exit 4
        ;;
    esac
    if [ ! -s "$json_file" ]; then
      printf 'No published release yet.\n' >&2
      printf 'Releases: %s\n' "$releases_url" >&2
      exit 2
    fi
  fi

  release_tag=$(read_release "$json_file" tag)
  if [ -z "$release_tag" ]; then
    printf 'No published release yet.\n' >&2
    printf 'Releases: %s\n' "$releases_url" >&2
    exit 2
  fi
fi

asset_name=""
asset_url=""
asset_api=""

if [ -n "$archive" ]; then
  if [ ! -f "$archive" ]; then
    printf 'Archive not found: %s\n' "$archive" >&2
    exit 4
  fi
  asset_name=$(basename "$archive")
  asset_url=$archive
else
  if ! picked=$(read_release "$json_file" asset); then
    printf 'No usable .dmg or .zip asset in release %s.\n' "$release_tag" >&2
    asset_names=$(read_release "$json_file" names)
    if [ -n "$asset_names" ]; then
      printf 'Assets:\n' >&2
      while IFS= read -r name; do
        printf '  %s\n' "$name" >&2
      done <<EOF
$asset_names
EOF
    fi
    exit 3
  fi
  asset_name=${picked%%$'\t'*}
  asset_rest=${picked#*$'\t'}
  asset_url=${asset_rest%%$'\t'*}
  asset_api=${asset_rest#*$'\t'}
fi

lower_name=$(printf '%s' "$asset_name" | tr '[:upper:]' '[:lower:]')
case "$lower_name" in
  *.dmg)
    archive_kind="dmg"
    verify_step="verify the disk image with hdiutil"
    ;;
  *.zip)
    archive_kind="zip"
    verify_step="verify the zip with unzip"
    ;;
  *)
    printf 'Cannot install %s: expected a .dmg or .zip.\n' "$asset_name" >&2
    exit 4
    ;;
esac

if [ "$dry_run" = 1 ]; then
  printf 'Chet release %s\n' "$release_tag"
  printf '  tag        %s\n' "$release_tag"
  printf '  asset      %s\n' "$asset_name"
  printf '  url        %s\n' "$asset_url"
  printf '  target     %s\n' "$target"
  printf '  steps      download to a temporary directory\n'
  printf '             %s\n' "$verify_step"
  printf '             quit check, replace %s/chet.app, clear quarantine\n' "$target"
  exit 0
fi

if [ -n "$archive" ]; then
  file=$archive
else
  file="$tmp/$asset_name"
  asset_curl_args=(-fsSL --retry 2 -H 'Accept: application/octet-stream')
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    asset_curl_args+=(-H "Authorization: Bearer $GITHUB_TOKEN")
  fi
  if ! curl "${asset_curl_args[@]}" -o "$file" "${asset_api:-$asset_url}"; then
    printf 'Download failed: %s\n' "$asset_name" >&2
    exit 4
  fi
fi

if [ ! -s "$file" ]; then
  printf 'Downloaded asset is empty: %s\n' "$asset_name" >&2
  exit 4
fi

if [ "$archive_kind" = "dmg" ]; then
  if ! hdiutil verify "$file" >/dev/null 2>&1; then
    printf 'Integrity check failed: %s\n' "$asset_name" >&2
    exit 4
  fi
else
  if ! unzip -tq "$file" >/dev/null 2>&1; then
    printf 'Integrity check failed: %s\n' "$asset_name" >&2
    exit 4
  fi
fi

if pgrep -x chet >/dev/null 2>&1; then
  printf 'Quit Chet, then run this again.\n' >&2
  exit 5
fi

if [ "$archive_kind" = "dmg" ]; then
  mount_point="$tmp/mount"
  mkdir -p "$mount_point"
  if ! hdiutil attach -nobrowse -readonly -mountpoint "$mount_point" "$file" >/dev/null 2>&1; then
    printf 'Cannot attach %s.\n' "$asset_name" >&2
    exit 7
  fi
  mounted=1
  source_dir=$mount_point
else
  source_dir="$tmp/unpack"
  mkdir -p "$source_dir"
  if ! ditto -x -k "$file" "$source_dir" >/dev/null 2>&1; then
    printf 'Cannot unpack %s.\n' "$asset_name" >&2
    exit 7
  fi
fi

app_count=0
app_path=""
for candidate in "$source_dir"/*.app; do
  if [ -d "$candidate" ]; then
    app_count=$((app_count + 1))
    app_path=$candidate
  fi
done
if [ "$app_count" -ne 1 ]; then
  printf 'Expected exactly one top-level .app in %s, found %s.\n' "$asset_name" "$app_count" >&2
  exit 7
fi

archs=$(lipo -archs "$app_path/Contents/MacOS/chet" 2>/dev/null || true)
case "$archs" in
  *arm64*) ;;
  *)
    printf 'The bundle is not arm64: %s\n' "${archs:-no binary}" >&2
    exit 7
    ;;
esac

found_bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist" 2>/dev/null || true)
if [ "$found_bundle_id" != "$bundle_id" ]; then
  printf 'Unexpected bundle identifier: %s\n' "${found_bundle_id:-missing}" >&2
  exit 7
fi

destination="$target/chet.app"

if ! mkdir -p "$target" 2>/dev/null; then
  printf 'Cannot create %s.\n' "$target" >&2
  printf 'Create it, then run this:\n' >&2
  printf '  sudo ditto %q %q\n' "$app_path" "$destination" >&2
  exit 6
fi

if [ ! -w "$target" ]; then
  printf '%s is not writable.\n' "$target" >&2
  printf 'Copy the bundle yourself, then clear quarantine:\n' >&2
  printf '  sudo ditto %q %q\n' "$app_path" "$destination" >&2
  exit 6
fi

backup="$tmp/previous-chet.app"
had_previous=0

restore_previous() {
  rm -rf "$destination"
  if [ "$had_previous" = 1 ]; then
    if mv "$backup" "$destination"; then
      had_previous=0
    fi
  fi
}

if [ -e "$destination" ]; then
  if ! mv "$destination" "$backup"; then
    printf 'Cannot move the existing bundle at %s.\n' "$destination" >&2
    exit 7
  fi
  had_previous=1
fi

if ! ditto "$app_path" "$destination"; then
  restore_previous
  printf 'Install failed; the previous bundle was left in place.\n' >&2
  exit 7
fi

xattr -dr com.apple.quarantine "$destination" >/dev/null 2>&1 || true
remaining_quarantine=$(xattr -p com.apple.quarantine "$destination" 2>/dev/null || true)
if [ -n "$remaining_quarantine" ]; then
  restore_previous
  printf 'Could not clear the quarantine attribute.\n' >&2
  exit 7
fi

installed_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$destination/Contents/Info.plist" 2>/dev/null || true)
installed_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$destination/Contents/Info.plist" 2>/dev/null || true)

if [ -n "$installed_version" ] && [ -n "$installed_build" ]; then
  :
else
  restore_previous
  printf 'The installed bundle is missing its version fields.\n' >&2
  exit 7
fi

if [ "$had_previous" = 1 ]; then
  rm -rf "$backup"
  had_previous=0
fi

printf 'Chet %s installed.\n' "$installed_version"
printf '  tag        %s\n' "$release_tag"
printf '  asset      %s\n' "$asset_name"
printf '  path       %s\n' "$destination"
printf '  version    %s\n' "$installed_version"
printf '  build      %s\n' "$installed_build"
printf '  Quarantine cleared.\n'
