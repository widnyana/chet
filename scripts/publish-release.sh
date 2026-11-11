#!/bin/bash
set -euo pipefail

usage() {
  cat <<'EOF'
Publish a Chet release from this machine.

Usage: bash scripts/publish-release.sh [options]

Options:
  --draft          Create the GitHub release as a draft
  --dry-run        Print the version, tag, artifacts, and every command; run nothing
  --skip-build     Reuse the existing dist/chet.dmg and dist/chet.zip
  --clean          Run `mise run clean` before the build
  --tag TAG        Release tag (default: $CHET_TAG, else v<version>)
  --notes TEXT     Release notes (default: generated notes)
  --help           Show this help and exit

Exit codes:
  0  published, or the dry-run plan printed
  2  working tree is dirty
  3  tag already exists locally or on origin
  4  gh is missing or not authenticated for github.com
  5  build, artifact, or build-number failure
  8  usage error

Examples:
  mise run publish -- --draft
  mise run publish -- --dry-run
  mise run publish -- --tag v0.11.0 --notes "Faster scans."
EOF
}

draft=0
dry_run=0
skip_build=0
clean=0
tag_arg=""
notes=""
notes_set=0

while [ $# -gt 0 ]; do
  case "$1" in
    --draft)
      draft=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    --skip-build)
      skip_build=1
      shift
      ;;
    --clean)
      clean=1
      shift
      ;;
    --tag)
      if [ $# -lt 2 ] || [ -z "$2" ]; then
        printf 'Missing value for --tag.\n' >&2
        usage >&2
        exit 8
      fi
      tag_arg=$2
      shift 2
      ;;
    --notes)
      if [ $# -lt 2 ]; then
        printf 'Missing value for --notes.\n' >&2
        usage >&2
        exit 8
      fi
      notes=$2
      notes_set=1
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

root=$(git rev-parse --show-toplevel)
cd "$root"

plist="Chet/Info.plist"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist" 2>/dev/null || true)
if [ -z "$version" ]; then
  printf 'Chet/Info.plist has no CFBundleShortVersionString.\n' >&2
  exit 5
fi

if [ -n "$tag_arg" ]; then
  tag=$tag_arg
elif [ -n "${CHET_TAG:-}" ]; then
  tag=$CHET_TAG
else
  tag="v$version"
fi

if [ -n "$(git status --porcelain)" ]; then
  printf 'The working tree is dirty. Commit or stash the changes first.\n' >&2
  exit 2
fi

if ! command -v gh >/dev/null 2>&1; then
  printf 'gh is not installed. Install it with mise, then run gh auth login -h github.com.\n' >&2
  exit 4
fi

if ! gh auth status -h github.com >/dev/null 2>&1; then
  printf 'gh is not authenticated for github.com. Run gh auth login -h github.com.\n' >&2
  exit 4
fi

if git rev-parse -q --verify "refs/tags/$tag" >/dev/null 2>&1; then
  printf 'Tag %s already exists locally.\n' "$tag" >&2
  exit 3
fi

remote_tag=$(git ls-remote --tags origin "refs/tags/$tag")
if [ -n "$remote_tag" ]; then
  printf 'Tag %s already exists on origin.\n' "$tag" >&2
  exit 3
fi

current_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist" 2>/dev/null || true)
case "$current_build" in
  ''|*[!0-9]*) planned_build="<next>" ;;
  *) planned_build=$((current_build + 1)) ;;
esac

release_args=(release create "$tag" dist/chet.dmg dist/chet.zip --title "Chet $version")
if [ "$notes_set" = 1 ]; then
  release_args+=(--notes "$notes")
else
  release_args+=(--generate-notes)
fi
if [ "$draft" = 1 ]; then
  release_args+=(--draft)
fi

if [ "$dry_run" = 1 ]; then
  printf 'Chet %s release plan\n' "$version"
  printf '  version    %s\n' "$version"
  printf '  tag        %s\n' "$tag"
  printf '  artifacts  dist/chet.dmg\n'
  printf '             dist/chet.zip\n'
  printf '  draft      %s\n' "$draft"
  printf '  commit     chore(release): %s build %s\n' "$version" "$planned_build"
  printf 'Commands:\n'
  if [ "$skip_build" = 0 ]; then
    if [ "$clean" = 1 ]; then
      printf '  mise run clean\n'
    fi
    printf '  mise run dmg\n'
    printf '  git add Chet/Info.plist\n'
    printf '  git commit -m %q\n' "chore(release): $version build $planned_build"
  fi
  printf '  git tag -a %q -m %q\n' "$tag" "Chet $version"
  printf '  git push origin HEAD\n'
  printf '  git push origin %q\n' "$tag"
  printf '  gh'
  printf ' %q' "${release_args[@]}"
  printf '\n'
  printf '  gh release view %q --json isDraft,tagName,assets\n' "$tag"
  exit 0
fi

if [ "$skip_build" = 0 ]; then
  if [ "$clean" = 1 ]; then
    if ! mise run clean; then
      printf 'mise run clean failed.\n' >&2
      exit 5
    fi
  fi
  before_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
  if ! mise run dmg; then
    printf 'mise run dmg failed.\n' >&2
    exit 5
  fi
  after_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
  if [ "$after_build" = "$before_build" ]; then
    printf 'The build number did not change.\n' >&2
    exit 5
  fi
  git add Chet/Info.plist
  git commit -m "chore(release): $version build $after_build"
else
  after_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$plist")
fi

if [ ! -f dist/chet.dmg ] || [ ! -f dist/chet.zip ]; then
  printf 'dist/chet.dmg and dist/chet.zip are both required.\n' >&2
  exit 5
fi

git tag -a "$tag" -m "Chet $version"
git push origin HEAD
git push origin "$tag"
release_output=$(gh "${release_args[@]}")
release_url=$(printf '%s' "$release_output" | tr -d '\n')

release_view=$(gh release view "$tag" --json isDraft,tagName,assets)
asset_names=$(printf '%s\n' "$release_view" | python3 -c 'import json, sys
data = json.load(sys.stdin)
for asset in data.get("assets") or []:
    print(asset.get("name") or "")')

for wanted in chet.dmg chet.zip; do
  found=0
  while IFS= read -r name; do
    if [ "$name" = "$wanted" ]; then
      found=1
    fi
  done <<EOF
$asset_names
EOF
  if [ "$found" = 0 ]; then
    printf 'Release %s is missing %s.\n' "$tag" "$wanted" >&2
    exit 5
  fi
done

printf 'Chet %s published.\n' "$version"
printf '  tag        %s\n' "$tag"
printf '  version    %s\n' "$version"
printf '  build      %s\n' "$after_build"
printf '  asset      chet.dmg\n'
printf '  asset      chet.zip\n'
printf '  release    %s\n' "$release_url"
