#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────
# Constants
# ──────────────────────────────────────────────
SUNSHINE_BIN="/Applications/Sunshine.app/Contents/MacOS/sunshine"
SUNSHINE_CONF="$HOME/.config/sunshine/sunshine.conf"
STATE_DIR="$HOME/.config/remote-mode"
STATE_FILE="$STATE_DIR/state"
BACKUP_CONF="$STATE_DIR/backup.conf"

VIRTUAL_NAME_LIKE="Virtual"
PHYSICAL_NAME_LIKE="LG"
VIRTUAL_KEYWORD="BetterDisplay"
DISPLAY_SETTLE_SECS=4
SUNSHINE_SETTLE_SECS=2
REMOTE_BRIGHTNESS=0
LOCAL_BRIGHTNESS=100

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

    if ! command -v betterdisplaycli &>/dev/null; then
        missing+=("betterdisplaycli")
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
# Parse BetterDisplay display index from --list-displays
# ──────────────────────────────────────────────
parse_sunshine_index() {
    local list="$1"
    # Expected line format (example):
    #   Index: 2 | Name: BetterDisplay Virtual Display
    # We extract the first numeric index whose Name line contains VIRTUAL_KEYWORD.
    echo "$list" \
        | grep -i "$VIRTUAL_KEYWORD" \
        | grep -o 'Index:[[:space:]]*[0-9]*' \
        | grep -o '[0-9]*' \
        | head -1 \
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
    betterdisplaycli set -namelike="$VIRTUAL_NAME_LIKE" -state=off || true
    betterdisplaycli set -namelike="$PHYSICAL_NAME_LIKE" -brightness="$LOCAL_BRIGHTNESS" || true
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
    betterdisplaycli set -namelike="$VIRTUAL_NAME_LIKE" -state=on -main

    # 2. Wait for display layout to stabilise
    info "Waiting ${DISPLAY_SETTLE_SECS}s for display layout to settle …"
    sleep "$DISPLAY_SETTLE_SECS"

    # 3. Dim physical display
    info "Dimming physical display (brightness → ${REMOTE_BRIGHTNESS}) …"
    betterdisplaycli set -namelike="$PHYSICAL_NAME_LIKE" -brightness="$REMOTE_BRIGHTNESS"

    # 4. Discover virtual display index in Sunshine
    info "Querying Sunshine display list …"
    local display_list
    display_list="$("$SUNSHINE_BIN" --list-displays 2>&1)" || true

    local target_index
    target_index="$(parse_sunshine_index "$display_list")"

    if [[ -z "$target_index" ]] || ! [[ "$target_index" =~ ^[0-9]+$ ]]; then
        die "Could not determine BetterDisplay index from Sunshine. Output was:\n${display_list}"
    fi

    info "BetterDisplay index in Sunshine: $target_index"

    # 5. Update sunshine.conf (atomic)
    conf_set "output_name" "$target_index"

    # 6. Restart Sunshine service
    info "Restarting Sunshine …"
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
    if betterdisplaycli set -namelike="$VIRTUAL_NAME_LIKE" -state=off 2>/dev/null; then
        info "Virtual display deactivated."
    else
        warn "Could not deactivate virtual display; continuing …"
    fi

    sleep 2

    if betterdisplaycli set -namelike="$PHYSICAL_NAME_LIKE" -brightness="$LOCAL_BRIGHTNESS" 2>/dev/null; then
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

    printf '\n--- Display list (from Sunshine) ---\n'
    if [[ -x "$SUNSHINE_BIN" ]]; then
        "$SUNSHINE_BIN" --list-displays 2>&1 || echo "(error querying displays)"
    else
        echo "(Sunshine binary not found at $SUNSHINE_BIN)"
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
