# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Does

Automates switching a Mac Mini M4 Pro between two streaming modes:

- **REMOTE_MODE**: Activates a BetterDisplay 16:10 virtual display, dims the physical LG DualUp (8:9) screen to 0, pins Sunshine to stream that virtual display. Intended to be triggered via SSH from a Chromebook.
- **LOCAL_MODE**: Deactivates the virtual display, restores LG brightness, resets Sunshine to output index 0.

The core problem is that streaming an 8:9 physical display to a 16:10 Chromebook produces large black bars. The fix is to stream a virtual 16:10 display instead.

## Commands

```bash
# Install symlinks into ~/bin/
bash install.sh

# Enter remote mode (run via SSH before opening Moonlight)
remote-up

# Return to local mode (run when back at the physical machine)
remote-down

# Read-only status: state, sunshine.conf, process, display list, tailscale
remote-status

# Remove symlinks from ~/bin/
bash uninstall.sh
```

`remote-up`, `remote-down`, and `remote-status` are all symlinks to `remote.sh`, which dispatches via `basename "$0"`. You can also call `./remote.sh up|down|status` directly.

## Architecture

### Single-script dispatch (`remote.sh`)

All logic lives in one file. `main()` reads `basename "$0"` to determine which subcommand was invoked, falling back to `$1` when called directly.

### State machine

Persistent state is stored in `~/.config/remote-mode/state` (`local` or `remote`). `cmd_up` is idempotent — if state is already `remote`, it exits cleanly.

### Atomic config writes

`conf_set()` writes to a `mktemp` file then `mv`s it into place, preventing a corrupt `sunshine.conf` on interruption.

### Rollback trap (`cmd_up` only)

`cmd_up` sets `_ROLLBACK_ACTIVE=true` and registers `trap rollback ERR EXIT` immediately after `backup_conf`. On any failure, `rollback()` restores the config, turns off the virtual display, restores brightness, and restarts Sunshine. The trap is disarmed (`trap - ERR EXIT`) only after all steps succeed. `cmd_down` does NOT use a rollback trap — it's intentionally best-effort, continuing past failures.

### Display index discovery

`parse_sunshine_index()` runs `$SUNSHINE_BIN --list-displays`, greps for lines containing `"BetterDisplay"`, and extracts the numeric `Index:` field. This index is written to `output_name` in `sunshine.conf` and is dynamic — it can change if displays are added/removed.

## Key File Locations

| Path | Purpose |
|------|---------|
| `~/.config/sunshine/sunshine.conf` | Sunshine config; `output_name` key selects which display to stream |
| `~/.config/remote-mode/state` | Persisted mode (`local` / `remote`) |
| `~/.config/remote-mode/backup.conf` | Pre-`cmd_up` snapshot of `sunshine.conf` for rollback |
| `/opt/homebrew/opt/sunshine/bin/sunshine` | Sunshine binary (for `--list-displays`); installed via `brew install lizardbyte/homebrew/sunshine` |

## Dependencies

All checked at startup by `check_deps()`:
- `betterdisplaycli` — controls virtual display on/off and physical display brightness
- Sunshine binary at `/opt/homebrew/opt/sunshine/bin/sunshine` (install via `brew tap lizardbyte/homebrew && brew install lizardbyte/homebrew/sunshine`)
- `brew` — used to restart the Sunshine service (`brew services restart sunshine`)
- `tailscale` — optional, only shown in `remote-status`
