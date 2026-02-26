#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$HOME/bin"
CMDS=(remote-up remote-down remote-status)

for cmd in "${CMDS[@]}"; do
    if [[ -L "$BIN_DIR/$cmd" ]]; then
        rm "$BIN_DIR/$cmd"
        echo "Removed: $BIN_DIR/$cmd"
    else
        echo "Skipped: $BIN_DIR/$cmd (not a symlink or not found)"
    fi
done

echo "Uninstall complete."
