#!/usr/bin/env bash
set -euo pipefail

export DRY_RUN=1
readonly DRY_RUN
printf 'DRY_RUN=1 enforced\n'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_DIR"

MODE=local
ALLOW_FOCUS=0
ALLOW_ACTIVE_INPUT=0
BUILD_ONLY=0
SESSION_USER=""
ONLY_TESTS=()

usage() {
    printf 'usage: %s [--only <test>]... [--build-only] [--mode local|session] [--allow-focus] [--allow-active-input] [--session-user <name>]\n' "$0" >&2
    exit 2
}

require_idle_machine() {
    if ioreg -n Root -d1 -a 2>/dev/null | grep -q CGSSessionScreenIsLocked; then
        fail 7 "the screen is locked"
    fi
    if [ "$ALLOW_ACTIVE_INPUT" = 1 ]; then
        return 0
    fi
    local idle_ns
    idle_ns=$(ioreg -c IOHIDSystem 2>/dev/null | sed -n 's/.*HIDIdleTime" = \([0-9]*\).*/\1/p' | head -1)
    if [ -z "$idle_ns" ]; then
        fail 7 "cannot read keyboard idle time"
    fi
    if [ "$idle_ns" -lt 20000000000 ]; then
        fail 7 "the machine is in use (idle under 20 s); pass --allow-active-input only when you are not typing"
    fi
}

fail() {
    local code="$1"
    shift
    printf 'uitest: %s\n' "$*" >&2
    exit "$code"
}

while [ "$#" -gt 0 ]; do
    case "$1" in
        --only)
            [ "$#" -ge 2 ] || usage
            case "$2" in
                '' | -*) usage ;;
            esac
            ONLY_TESTS+=("$2")
            shift 2
            ;;
        --build-only)
            BUILD_ONLY=1
            shift
            ;;
        --mode)
            [ "$#" -ge 2 ] || usage
            case "$2" in
                local | session) MODE="$2" ;;
                *) usage ;;
            esac
            shift 2
            ;;
        --allow-focus)
            ALLOW_FOCUS=1
            shift
            ;;
        --allow-active-input)
            ALLOW_ACTIVE_INPUT=1
            shift
            ;;
        --session-user)
            [ "$#" -ge 2 ] || usage
            [ -n "$2" ] || usage
            SESSION_USER="$2"
            shift 2
            ;;
        -h | --help)
            usage
            ;;
        *)
            usage
            ;;
    esac
done

[ "${#ONLY_TESTS[@]}" -gt 0 ] || ONLY_TESTS=(chetUITests)

command -v xcodegen >/dev/null 2>&1 ||
    fail 2 "xcodegen is missing; install it with mise install xcodegen"
command -v xcodebuild >/dev/null 2>&1 ||
    fail 2 "xcodebuild is missing; install Xcode and select it with xcode-select"
command -v swiftc >/dev/null 2>&1 ||
    fail 2 "swiftc is missing; install Xcode and select it with xcode-select"

git -c safe.directory="$REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 ||
    fail 2 "$REPO_DIR is not a git work tree"

printf 'uitest: git status\n'
status_output="$(git -c safe.directory="$REPO_DIR" status --porcelain=v1 -uall)"
if [ -z "$status_output" ]; then
    printf '  (clean)\n'
else
    printf '%s\n' "$status_output"
fi

for pid in $(pgrep -x chet 2>/dev/null || true); do
    exe=""
    while IFS= read -r line; do
        case "$line" in
            n*)
                exe="${line#n}"
                break
                ;;
        esac
    done < <(/usr/sbin/lsof -p "$pid" -a -d txt -Fn 2>/dev/null || true)
    if [ -z "$exe" ]; then
        exe="$(ps -p "$pid" -o command= 2>/dev/null || true)"
        exe="${exe%% *}"
    fi
    [ -n "$exe" ] || continue
    case "$exe" in
        */.build/*) ;;
        *)
            if [ "$ALLOW_FOCUS" -eq 1 ]; then
                printf 'uitest: allowing chet pid %s outside .build: %s\n' "$pid" "$exe" >&2
            else
                fail 3 "chet pid $pid runs outside .build: $exe (use --allow-focus to override)"
            fi
            ;;
    esac
done

helper_pids="$(pgrep -x chet-helper 2>/dev/null || true)"
if [ -n "$helper_pids" ]; then
    fail 4 "chet-helper is running (pid $(printf '%s' "$helper_pids" | tr '\n' ' ')); stop it first"
fi

AXDRV="$REPO_DIR/.build/tools/axdrv"
needs_build=0
if [ ! -x "$AXDRV" ]; then
    needs_build=1
fi
for source in "$REPO_DIR/scripts/axdrv.swift" "$REPO_DIR/ChetCore/Sources/ChetCore/AXSelector.swift"; do
    if [ "$source" -nt "$AXDRV" ]; then
        needs_build=1
    fi
done
if [ "$needs_build" -eq 1 ] || [ "$BUILD_ONLY" -eq 1 ]; then
    mkdir -p "$REPO_DIR/.build/tools"
    swiftc -O \
        "$REPO_DIR/scripts/axdrv.swift" \
        "$REPO_DIR/ChetCore/Sources/ChetCore/AXSelector.swift" \
        -o "$AXDRV"
fi
printf 'uitest: axdrv ready at %s\n' "$AXDRV"

if [ "$BUILD_ONLY" -eq 1 ]; then
    printf 'uitest: build-only complete\n'
    exit 0
fi

HOME_DIR="${HOME:-}"
LAUNCH_AS_SESSION=0
SESSION_UID=""

if [ "$MODE" = session ]; then
    [ -n "$SESSION_USER" ] || fail 2 "--mode session needs --session-user <name>"
    [ "$(id -u)" -eq 0 ] ||
        fail 5 "session mode needs root; rerun as: sudo bash scripts/uitest.sh --mode session --session-user $SESSION_USER"
    id -u "$SESSION_USER" >/dev/null 2>&1 ||
        fail 5 "account $SESSION_USER does not exist; create it with: sudo sysadminctl -addUser $SESSION_USER"
    SESSION_UID="$(id -u "$SESSION_USER")"
    launchctl asuser "$SESSION_UID" /usr/bin/true >/dev/null 2>&1 ||
        fail 5 "no GUI session for $SESSION_USER; log in to that account once, then rerun: sudo bash scripts/uitest.sh --mode session --session-user $SESSION_USER"
    home_line="$(dscl . -read "/Users/$SESSION_USER" NFSHomeDirectory 2>/dev/null || true)"
    HOME_DIR="${home_line#NFSHomeDirectory: }"
    HOME_DIR="${HOME_DIR%%$'\n'*}"
    [ -n "$HOME_DIR" ] && [ -d "$HOME_DIR" ] ||
        fail 5 "cannot read the home directory of $SESSION_USER"
    USER_TMP="$(/usr/bin/sudo -u "$SESSION_USER" /usr/bin/getconf DARWIN_USER_TEMP_DIR)"
    USER_TMP="${USER_TMP%/}"
    [ -n "$USER_TMP" ] && [ -d "$USER_TMP" ] ||
        fail 5 "cannot read the temporary directory of $SESSION_USER"
    /usr/bin/sudo -u "$SESSION_USER" test -w "$USER_TMP" ||
        fail 5 "the temporary directory $USER_TMP is not writable by $SESSION_USER"
    SCRATCH_PARENT="$USER_TMP"
    LAUNCH_AS_SESSION=1
else
    SCRATCH_PARENT="${TMPDIR:-/tmp}"
    SCRATCH_PARENT="${SCRATCH_PARENT%/}"
    [ -d "$SCRATCH_PARENT" ] || fail 2 "scratch parent $SCRATCH_PARENT does not exist"
    SCRATCH_PARENT="$(cd "$SCRATCH_PARENT" && pwd -P)"
    [ -w "$SCRATCH_PARENT" ] || fail 2 "scratch parent $SCRATCH_PARENT is not writable"
fi

[ -n "$HOME_DIR" ] && [ -d "$HOME_DIR" ] || fail 2 "cannot read the home directory for the test run"

case "$SCRATCH_PARENT" in
    /var/folders/* | /private/var/folders/* | /tmp | /tmp/* | /private/tmp | /private/tmp/*) ;;
    *) fail 2 "scratch parent $SCRATCH_PARENT is not under /var/folders or /tmp" ;;
esac

if [ "$LAUNCH_AS_SESSION" -eq 1 ]; then
    ROOT="$(/usr/bin/sudo -u "$SESSION_USER" /usr/bin/mktemp -d "$SCRATCH_PARENT/chet-uitest.XXXXXX")"
else
    ROOT="$(mktemp -d "$SCRATCH_PARENT/chet-uitest.XXXXXX")"
fi

if [ "$LAUNCH_AS_SESSION" -eq 0 ]; then
    require_idle_machine
fi

trap 'if [ -n "${ROOT:-}" ] && [ -d "$ROOT" ]; then rm -rf -- "$ROOT"; fi' EXIT

USER_PATHS=(
    "$HOME_DIR/Library/Application Support"
    "$HOME_DIR/Library/Preferences"
    "$HOME_DIR/Library/Logs/chet"
    "$HOME_DIR/Library/Caches/id.web.widnyana.chet"
    "$HOME_DIR/.Trash"
)

snapshot() {
    git -c safe.directory="$REPO_DIR" status --porcelain=v1 -uall
    for path in "${USER_PATHS[@]}"; do
        stat -f '%m %z %N' "$path" 2>/dev/null || printf 'missing %s\n' "$path"
    done
}

snapshot >"$ROOT/before"
printf 'uitest: scratch root %s\n' "$ROOT"

XCODEBUILD_BIN="$(command -v xcodebuild)"
XCODE_ARGS=(
    test
    -project chet.xcodeproj
    -scheme chet
    -configuration Debug
    -destination 'platform=macOS'
    -derivedDataPath .build/xc
)
for test_id in "${ONLY_TESTS[@]}"; do
    XCODE_ARGS+=("-only-testing:$test_id")
done

status=0
if [ "$LAUNCH_AS_SESSION" -eq 1 ]; then
    launchctl asuser "$SESSION_UID" /usr/bin/sudo -u "$SESSION_USER" /usr/bin/env \
        DRY_RUN=1 HOME="$HOME_DIR" TMPDIR="$ROOT" \
        CHET_UITEST_ROOT="$ROOT" CHET_AXDRV="$AXDRV" \
        "$XCODEBUILD_BIN" "${XCODE_ARGS[@]}" || status=$?
else
    env DRY_RUN=1 TMPDIR="$ROOT" CHET_UITEST_ROOT="$ROOT" CHET_AXDRV="$AXDRV" \
        "$XCODEBUILD_BIN" "${XCODE_ARGS[@]}" || status=$?
fi

snapshot >"$ROOT/after"

if ! cmp -s "$ROOT/before" "$ROOT/after"; then
    printf 'uitest: git status or a user path changed during the run\n' >&2
    diff -u "$ROOT/before" "$ROOT/after" >&2 || true
    exit 6
fi

exit "$status"
