#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Constants
# ──────────────────────────────────────────────
SUNSHINE_BIN="/opt/homebrew/opt/sunshine/bin/sunshine"
SUNSHINE_CONF="$HOME/.config/sunshine/sunshine.conf"
STATE_DIR="$HOME/.config/remote-mode"
STATE_FILE="$STATE_DIR/state"
BACKUP_CONF="$STATE_DIR/backup.conf"

BDBIN="/Applications/BetterDisplay.app/Contents/MacOS/BetterDisplay"
VIRTUAL_NAME_LIKE="虚拟"
PHYSICAL_NAME_LIKE="LG"
SUNSHINE_LOG="$HOME/.config/sunshine/sunshine.log"
DISPLAY_SETTLE_SECS=4
SUNSHINE_SETTLE_SECS=2
REMOTE_BRIGHTNESS=0
LOCAL_BRIGHTNESS=1

# ──────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────
die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf 'WARN:  %s\n' "$*" >&2
}

info() {
    printf 'INFO:  %s\n' "$*"
}

# ──────────────────────────────────────────────
# Dependency check
# ──────────────────────────────────────────────
check_deps() {
    local missing=()

    if [[ ! -x "$BDBIN" ]]; then
        missing+=("BetterDisplay.app (expected at $BDBIN)")
    fi

    if [[ ! -x "$SUNSHINE_BIN" ]]; then
        missing+=("Sunshine.app (expected at $SUNSHINE_BIN)")
    fi

    if ! command -v brew &>/dev/null; then
        missing+=("brew (Homebrew)")
    fi

    if (( ${#missing[@]} > 0 )); then
        die "Missing dependencies: ${missing[*]}"
    fi
}

# ──────────────────────────────────────────────
# sunshine.conf helpers (atomic write)
# ──────────────────────────────────────────────
conf_set() {
    local key="$1"
    local val="$2"
    local tmpfile
    tmpfile="$(mktemp)"

    if [[ -f "$SUNSHINE_CONF" ]]; then
        # Replace existing key or append
        if grep -q "^${key}\s*=" "$SUNSHINE_CONF" 2>/dev/null; then
            sed "s|^${key}\s*=.*|${key} = ${val}|" "$SUNSHINE_CONF" > "$tmpfile"
        else
            cp "$SUNSHINE_CONF" "$tmpfile"
            printf '%s = %s\n' "$key" "$val" >> "$tmpfile"
        fi
    else
        mkdir -p "$(dirname "$SUNSHINE_CONF")"
        printf '%s = %s\n' "$key" "$val" > "$tmpfile"
    fi

    mv "$tmpfile" "$SUNSHINE_CONF"
}

conf_get() {
    local key="$1"
    if [[ -f "$SUNSHINE_CONF" ]]; then
        grep "^${key}\s*=" "$SUNSHINE_CONF" 2>/dev/null \
            | sed 's/^[^=]*=\s*//' \
            | head -1 \
            || true
    fi
}

# ──────────────────────────────────────────────
# State helpers
# ──────────────────────────────────────────────
state_read() {
    if [[ -f "$STATE_FILE" ]]; then
        cat "$STATE_FILE"
    else
        echo "unknown"
    fi
}

state_write() {
    mkdir -p "$STATE_DIR"
    printf '%s\n' "$1" > "$STATE_FILE"
}

# ──────────────────────────────────────────────
# Backup / restore sunshine.conf
# ──────────────────────────────────────────────
backup_conf() {
    mkdir -p "$STATE_DIR"
    if [[ -f "$SUNSHINE_CONF" ]]; then
        cp "$SUNSHINE_CONF" "$BACKUP_CONF"
        info "Backed up sunshine.conf → $BACKUP_CONF"
    else
        info "No sunshine.conf to back up; backup skipped"
    fi
}

restore_conf() {
    if [[ -f "$BACKUP_CONF" ]]; then
        cp "$BACKUP_CONF" "$SUNSHINE_CONF"
        info "Restored sunshine.conf from backup"
    else
        warn "No backup file found; skipping restore"
    fi
}

# ──────────────────────────────────────────────
# Parse virtual display id from Sunshine log file
# ──────────────────────────────────────────────
parse_sunshine_index() {
    # Sunshine 2025.x logs display detection at startup:
    #   Info: Detected display: Virtual 16:10 (id: 16) connected: true
    # We grep for lines matching VIRTUAL_NAME_LIKE and extract the id number.
    if [[ ! -f "$SUNSHINE_LOG" ]]; then
        return
    fi
    grep "Detected display:" "$SUNSHINE_LOG" 2>/dev/null \
        | grep -i "$VIRTUAL_NAME_LIKE" \
        | tail -1 \
        | grep -oE '\(id:[[:space:]]*[0-9]+\)' \
        | grep -oE '[0-9]+' \
        || true
}

# ──────────────────────────────────────────────
# Rollback (trap on ERR / EXIT during cmd_up)
# ──────────────────────────────────────────────
_ROLLBACK_ACTIVE=false
_ROLLBACK_DONE=false

rollback() {
    [[ "$_ROLLBACK_ACTIVE" == true && "$_ROLLBACK_DONE" == false ]] || return 0
    _ROLLBACK_DONE=true
    warn "Rolling back to local mode …"
    restore_conf || true
    "$BDBIN" set -type=VirtualScreen -connected=off || true
    "$BDBIN" set -nameLike="$PHYSICAL_NAME_LIKE" -brightness="$LOCAL_BRIGHTNESS" || true
    brew services restart sunshine || true
    state_write "local"
    warn "Rollback complete."
}

# ──────────────────────────────────────────────
# cmd_up — enter REMOTE MODE
# ──────────────────────────────────────────────
cmd_up() {
    local current
    current="$(state_read)"
    if [[ "$current" == "remote" ]]; then
        info "Already in remote mode. Run 'remote-status' for details."
        return 0
    fi

    info "Entering remote mode …"
    check_deps
    backup_conf

    # Arm rollback trap
    _ROLLBACK_ACTIVE=true
    _ROLLBACK_DONE=false
    trap rollback ERR EXIT

    # 1. Enable virtual display and set as main
    info "Activating virtual display …"
    local vconn
    vconn="$("$BDBIN" get -type=VirtualScreen -connected 2>/dev/null || true)"
    if [[ "$vconn" != "on" ]]; then
        "$BDBIN" set -type=VirtualScreen -connected=on
    fi
    sleep 1
    "$BDBIN" set -type=VirtualScreen -main=on

    # 2. Wait for display layout to stabilise
    info "Waiting ${DISPLAY_SETTLE_SECS}s for display layout to settle …"
    sleep "$DISPLAY_SETTLE_SECS"

    # 3. Dim physical display
    info "Dimming physical display (brightness → ${REMOTE_BRIGHTNESS}) …"
    "$BDBIN" set -nameLike="$PHYSICAL_NAME_LIKE" -brightness="$REMOTE_BRIGHTNESS"

    # 4. Discover virtual display id from Sunshine log
    # Restart Sunshine so it re-detects displays with virtual display now active as main.
    info "Restarting Sunshine to detect updated display layout …"
    brew services restart sunshine
    sleep 5

    local target_index
    target_index="$(parse_sunshine_index)"

    if [[ -z "$target_index" ]] || ! [[ "$target_index" =~ ^[0-9]+$ ]]; then
        die "Could not determine virtual display id from Sunshine log ($SUNSHINE_LOG). Check that Sunshine started correctly."
    fi

    info "Virtual display id in Sunshine: $target_index"

    # 5. Update sunshine.conf (atomic)
    conf_set "output_name" "$target_index"

    # 6. Restart Sunshine so it streams the correct display
    info "Restarting Sunshine with output_name = ${target_index} …"
    brew services restart sunshine
    sleep "$SUNSHINE_SETTLE_SECS"

    # Success — disarm rollback trap
    trap - ERR EXIT
    _ROLLBACK_ACTIVE=false
    state_write "remote"
    info "Remote mode active. Sunshine output_name = ${target_index}"
}

# ──────────────────────────────────────────────
# cmd_down — return to LOCAL MODE
# ──────────────────────────────────────────────
cmd_down() {
    info "Returning to local mode …"

    # Each step is best-effort; we continue even on failure
    if "$BDBIN" set -type=VirtualScreen -connected=off 2>/dev/null; then
        info "Virtual display deactivated."
    else
        warn "Could not deactivate virtual display; continuing …"
    fi

    sleep 2

    if "$BDBIN" set -nameLike="$PHYSICAL_NAME_LIKE" -brightness="$LOCAL_BRIGHTNESS" 2>/dev/null; then
        info "Physical display brightness restored to ${LOCAL_BRIGHTNESS}."
    else
        warn "Could not restore brightness; continuing …"
    fi

    conf_set "output_name" "0"
    info "sunshine.conf output_name reset to 0."

    if brew services restart sunshine 2>/dev/null; then
        info "Sunshine restarted."
    else
        warn "Could not restart Sunshine via brew services; continuing …"
    fi

    state_write "local"
    info "Local mode active."
}

# ──────────────────────────────────────────────
# cmd_status — read-only status report
# ──────────────────────────────────────────────
cmd_status() {
    local state
    state="$(state_read)"
    printf '\n=== Remote-Mode Status ===\n'
    printf 'State file   : %s\n' "$state"
    printf 'output_name  : %s\n' "$(conf_get "output_name" || echo "(not set)")"

    printf '\n--- Sunshine service ---\n'
    brew services list 2>/dev/null | grep -i sunshine || echo "(brew services unavailable)"

    printf '\n--- Sunshine process ---\n'
    pgrep -fl sunshine || echo "(not running)"

    printf '\n--- Display list (from Sunshine log) ---\n'
    if [[ -f "$SUNSHINE_LOG" ]]; then
        grep "Detected display:" "$SUNSHINE_LOG" 2>/dev/null | tail -20 || echo "(no display entries in log)"
    else
        echo "(log not found at $SUNSHINE_LOG)"
    fi

    printf '\n--- Tailscale ---\n'
    if command -v tailscale &>/dev/null; then
        tailscale status 2>&1 | head -20
    else
        echo "(tailscale not found)"
    fi
    printf '\n'
}

# ──────────────────────────────────────────────
# Entry point — dispatch via basename or first arg
# ──────────────────────────────────────────────
main() {
    local self cmd
    self="$(basename "$0")"

    case "$self" in
        remote-up)     cmd="up"     ;;
        remote-down)   cmd="down"   ;;
        remote-status) cmd="status" ;;
        *)             cmd="${1:-}" ;;
    esac

    case "$cmd" in
        up)     cmd_up     ;;
        down)   cmd_down   ;;
        status) cmd_status ;;
        *)
            printf 'Usage: %s {up|down|status}\n' "$self" >&2
            exit 1
            ;;
    esac
}

main "$@"
