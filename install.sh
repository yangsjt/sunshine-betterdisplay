#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BIN_DIR="$HOME/bin"
CMDS=(remote-up remote-down remote-status)

mkdir -p "$BIN_DIR"
chmod +x "$SCRIPT_DIR/remote.sh"

for cmd in "${CMDS[@]}"; do
    ln -sf "$SCRIPT_DIR/remote.sh" "$BIN_DIR/$cmd"
    echo "Linked: $BIN_DIR/$cmd -> $SCRIPT_DIR/remote.sh"
done

mkdir -p "$HOME/.config/remote-mode" "$HOME/.config/sunshine"
echo "Install complete. Run: remote-status"
