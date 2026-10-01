#!/usr/bin/env bash
# vscode-push.sh — push report file(s) to the user's connected VS Code (Remote-SSH) window.
#
# Usage:
#   bash vscode-push.sh /abs/report.md [more files...]
#
# Behavior:
#   - Any missing file -> list missing on stderr, exit 1 (never silent).
#   - Socket discovery (kernel view first):
#       1. Read active unix sockets from the kernel table (/proc/net/unix), pick the
#          newest (mtime) 'vscode-ipc-*.sock' candidate. Kernel view only lists live
#          bound sockets, so stale socket files are naturally excluded, and the lookup
#          is path-independent.
#       2. If the kernel table is unreadable (non-Linux / no permission), fall back to
#          scanning ${XDG_RUNTIME_DIR:-/run/user/$(id -u)} for vscode-ipc-*.sock,
#          newest mtime wins. This is the only fallback layer.
#   - remote-cli discovery supports both server layouts:
#       new CLI layout: $VSCODE_SERVER_DIR/cli/servers/Stable-*/server/bin/remote-cli/code
#       old layout:     $VSCODE_SERVER_DIR/bin/*/bin/code
#     Newest (mtime) existing executable wins.
#   - Filesystem searches prefer fd (if installed), falling back to GNU find.
#   - The commit hash and socket uuid change on every VS Code upgrade / reconnect,
#     so everything is looked up fresh on every run — never cached, never hardcoded.
#   - Success -> exit 0; stdout confirms pushed files + socket used.
#   - Failure (VS Code not connected, or push itself failed) -> reason on stderr,
#     absolute file paths on stdout so the user can open them manually, non-zero exit.
#
# Env overrides (for tests only):
#   VSCODE_UNIX_TABLE  kernel unix-socket table (default /proc/net/unix)
#   VSCODE_SOCK_DIR    dir to scan for vscode-ipc-*.sock on fallback
#                      (default: ${XDG_RUNTIME_DIR:-/run/user/$(id -u)})
#   VSCODE_SERVER_DIR  vscode-server root (default: $HOME/.vscode-server)

set -u

SCRIPT_NAME=$(basename "$0")
VSCODE_UNIX_TABLE="${VSCODE_UNIX_TABLE:-/proc/net/unix}"
VSCODE_SOCK_DIR="${VSCODE_SOCK_DIR:-${XDG_RUNTIME_DIR:-/run/user/$(id -u)}}"
VSCODE_SERVER_DIR="${VSCODE_SERVER_DIR:-$HOME/.vscode-server}"

err() { echo "$SCRIPT_NAME: $*" >&2; }

# Fallback helper: tell the user where the files are so they can open them manually.
print_fallback_paths() {
    echo "Fallback: open the file(s) yourself:"
    printf '  %s\n' "$@"
}

# Filesystem search: prefer fd (if installed), fall back to GNU find.
# Prints candidate paths (absolute if root is absolute), one per line.
search_fs() { # <maxdepth> <name-pattern> <root>
    local out rc
    if command -v fd >/dev/null 2>&1; then
        out=$(fd -u --max-depth "$1" --glob "$2" "$3" 2>/dev/null); rc=$?
        # fd ran fine (even with zero matches) -> trust its output;
        # only an actual fd failure (non-zero rc, no output) falls through to find.
        if [ "$rc" -eq 0 ] || [ -n "$out" ]; then
            printf '%s\n' "$out"
            return 0
        fi
    fi
    find "$3" -maxdepth "$1" -name "$2" 2>/dev/null
}

# stdin: candidate paths -> stdout: the newest existing one by mtime (ties: first seen).
newest_by_mtime() {
    local best="" best_t=-1 t p
    while IFS= read -r p; do
        [ -n "$p" ] || continue
        [ -e "$p" ] || continue
        t=$(stat -c %Y "$p" 2>/dev/null) || continue
        if [ "$t" -gt "$best_t" ]; then best="$p"; best_t="$t"; fi
    done
    [ -n "$best" ] && printf '%s\n' "$best"
    return 0
}

if [ $# -lt 1 ]; then
    err "usage: $SCRIPT_NAME <file> [more files...]"
    exit 1
fi

# 1. Check all files exist; convert to absolute paths (no silent skips).
missing=()
files_abs=()
for f in "$@"; do
    if [ ! -f "$f" ]; then
        missing+=("$f")
    else
        files_abs+=("$(cd "$(dirname "$f")" && pwd)/$(basename "$f")")
    fi
done
if [ "${#missing[@]}" -gt 0 ]; then
    err "file(s) not found:"
    printf '  %s\n' "${missing[@]}" >&2
    exit 1
fi

# 2. Discover remote-cli: both layouts, newest existing executable wins.
remote_cli=$(
    search_fs 7 code "$VSCODE_SERVER_DIR" | while IFS= read -r cand; do
        case "$cand" in
            "$VSCODE_SERVER_DIR"/cli/servers/*/server/bin/remote-cli/code | \
            "$VSCODE_SERVER_DIR"/bin/*/bin/code)
                [ -x "$cand" ] && printf '%s\n' "$cand"
                ;;
        esac
    done | newest_by_mtime
)
if [ -z "$remote_cli" ]; then
    err "VS Code remote-cli not found under $VSCODE_SERVER_DIR (Remote-SSH server not installed?)."
    print_fallback_paths "${files_abs[@]}"
    exit 2
fi

# 3. Discover IPC socket: kernel table of active sockets first, dir scan fallback.
if [ -r "$VSCODE_UNIX_TABLE" ]; then
    ipc_sock=$(awk '$NF ~ /vscode-ipc-/ { print $NF }' "$VSCODE_UNIX_TABLE" | sort -u | newest_by_mtime)
else
    ipc_sock=$(search_fs 1 'vscode-ipc-*.sock' "$VSCODE_SOCK_DIR" | newest_by_mtime)
fi
if [ -z "$ipc_sock" ] || [ ! -S "$ipc_sock" ]; then
    err "No active vscode-ipc socket (checked kernel table $VSCODE_UNIX_TABLE, then dir $VSCODE_SOCK_DIR). VS Code window not connected?"
    print_fallback_paths "${files_abs[@]}"
    exit 3
fi

# 4. Push: each file opens its own tab; an already-open file just re-activates its tab.
VSCODE_IPC_HOOK_CLI="$ipc_sock" "$remote_cli" --goto "${files_abs[@]}"
push_rc=$?
if [ "$push_rc" -ne 0 ]; then
    err "push via remote-cli failed (exit $push_rc)."
    print_fallback_paths "${files_abs[@]}"
    exit 4
fi

echo "Pushed ${#files_abs[@]} file(s) to VS Code window via $ipc_sock:"
printf '  %s\n' "${files_abs[@]}"
exit 0
