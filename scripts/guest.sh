#!/usr/bin/env bash
set -euo pipefail

VM="${CHET_VM:-chet-uitest}"
SHARE="/Volumes/My Shared Files/chet"
GUEST_REPO="${CHET_GUEST_REPO:-/Users/admin/chet}"
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCES=(ChetCore/Sources Chet chetUITests scripts)
FIND_EXPR=(-type f \( -name '*.swift' -o -name '*.sh' \))

guest() {
    tart exec "$VM" zsh -lc "$1"
}

host_manifest() {
    (
        cd "$REPO_DIR"
        find "${SOURCES[@]}" "${FIND_EXPR[@]}" -print0 | xargs -0 md5 -r | LC_ALL=C sort -k2
    ) > "$1"
}

guest_manifest() {
    guest "
        cd '$GUEST_REPO' || exit 1
        { find ${SOURCES[*]} -type f -name '*.swift'; find ${SOURCES[*]} -type f -name '*.sh'; } |
            sort | xargs md5 -r | LC_ALL=C sort -k2 > '$SHARE/$1'
    "
}

compare() {
    local host="$1" guest="$2" out="$3"
    declare -A hh=() gh=()
    local hash path
    while read -r hash path; do hh["$path"]="$hash"; done < "$host"
    while read -r hash path; do gh["$path"]="$hash"; done < "$guest"
    : > "$out"
    for path in "${!hh[@]}"; do
        [[ "${gh[$path]:-}" == "${hh[$path]}" ]] || printf '%s\n' "$path" >> "$out"
    done
    printf '%s\n' "${#hh[@]}"
}

cmd_sync() {
    local stamp stage host_list guest_list mismatched total
    stamp="$(date +%s)"
    stage=".build/sync-$stamp"
    host_list="/tmp/chet-host-manifest.txt"
    guest_list="$REPO_DIR/$stage/guest-manifest.txt"
    mkdir -p "$REPO_DIR/$stage"

    guest "rsync -a --delete --exclude '.build' '$SHARE/' '$GUEST_REPO/' || true"

    host_manifest "$host_list"
    guest_manifest "$stage/guest-manifest.txt" || true

    total="$(compare "$host_list" "$guest_list" "$REPO_DIR/$stage/mismatch.txt")"
    mismatched="$(grep -c . "$REPO_DIR/$stage/mismatch.txt" || true)"
    printf 'mirror: %s files, %s stale in the guest\n' "$total" "$mismatched"

    if [[ "$mismatched" != 0 ]]; then
        local path
        : > "$REPO_DIR/$stage/list.txt"
        while read -r path; do
            mkdir -p "$(dirname "$REPO_DIR/$stage/$path")"
            cp "$REPO_DIR/$path" "$REPO_DIR/$stage/$path"
            printf '%s\n' "$path" >> "$REPO_DIR/$stage/list.txt"
        done < "$REPO_DIR/$stage/mismatch.txt"
        guest "
            cd '$GUEST_REPO' || exit 1
            while read -r p; do
                mkdir -p \"\$(dirname \"\$p\")\"
                cp '$SHARE/$stage/'\$p \"\$p\"
            done < '$SHARE/$stage/list.txt'
        "
    fi

    guest "cd '$GUEST_REPO' && xcodegen generate --quiet"

    guest_manifest "$stage/verify.txt" || true
    total="$(compare "$host_list" "$REPO_DIR/$stage/verify.txt" "$REPO_DIR/$stage/remaining.txt")"
    mismatched="$(grep -c . "$REPO_DIR/$stage/remaining.txt" || true)"
    if [[ "$mismatched" != 0 ]]; then
        printf 'mirror: %s files still stale after copy:\n' "$mismatched" >&2
        sed 's/^/  /' "$REPO_DIR/$stage/remaining.txt" >&2
        return 1
    fi
    printf 'mirror: %s files identical\n' "$total"
}

cmd_run() {
    local args
    args="$(printf '%q ' "$@")"
    guest "cd '$GUEST_REPO' && DRY_RUN=1 bash scripts/uitest.sh --allow-focus --allow-active-input $args"
}

cmd_cleanup() {
    guest "
        pkill -f 'xcodebuild test' || true
        pkill -f chetUITests-Runner || true
        pkill -f '$GUEST_REPO/.build/xc/Build/Products/Debug/chet.app/Contents/MacOS/chet' || true
        find \"\$HOME/Library/Containers/id.web.widnyana.chet.uitest.xctrunner/Data/tmp\" \
            -maxdepth 1 -name 'chet-uitest.*' -exec rm -rf {} + 2>/dev/null || true
        pgrep -fl 'xcodebuild|chetUITests-Runner|chet.app' || echo 'no test processes'
    "
}

case "${1:-}" in
    sync) shift; cmd_sync "$@" ;;
    run) shift; cmd_run "$@" ;;
    cleanup) shift; cmd_cleanup "$@" ;;
    *) printf 'usage: %s sync | run [uitest args] | cleanup\n' "$0" >&2; exit 2 ;;
esac
