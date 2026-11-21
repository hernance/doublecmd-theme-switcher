#!/bin/bash
# Changes the Double Commander theme. Two modes:
#   now   - quits DC gracefully (saves tabs/state), applies the complete theme
#           (colors.json + DarkMode in doublecmd.cfg), and reopens it if it was running.
#   stage - if DC is running: applies ONLY colors.json live (safe, DC never rewrites
#           it) and leaves the doublecmd.cfg DarkMode pending in a marker file, because
#           DC does rewrite its own doublecmd.cfg on quit and would overwrite the
#           change. The pending change is finished automatically, without asking for a
#           theme, the next time this script is invoked with DC already closed (any mode).
#           If DC is NOT running, "stage" applies everything at once (nothing to overwrite).
#
# Usage: dc_theme_phoenix.sh <theme-name> [now|stage]   (default: now)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/phoenix.log"
PENDING_FILE="$SCRIPT_DIR/.pending_cfg_theme"
DC_APP_NAME="Double Commander"
THEME="${1:-}"
MODE="${2:-now}"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }

is_running() { pgrep -f "$DC_APP_NAME" > /dev/null 2>&1; }

apply_pending_cfg_if_any() {
  # Only called once DC is confirmed not running. Finishes applying the DarkMode
  # that an earlier "stage" left pending because doublecmd.cfg can't be touched live.
  if [ -f "$PENDING_FILE" ]; then
    local pending_theme
    pending_theme="$(cat "$PENDING_FILE")"
    log "Pending change from an earlier stage: applying DarkMode of '$pending_theme' (doublecmd.cfg)..."
    if python3 "$SCRIPT_DIR/dc_theme_apply.py" --apply "$pending_theme" --only cfg >> "$LOG_FILE" 2>&1; then
      rm -f "$PENDING_FILE"
      log "Pending change applied and cleared."
    else
      log "ERROR: could not apply the pending change for '$pending_theme', leaving the marker in place."
    fi
  fi
}

if [ -z "$THEME" ]; then
  echo "Usage: $0 <theme-name> [now|stage]" >&2
  exit 1
fi

if [ "$MODE" != "now" ] && [ "$MODE" != "stage" ]; then
  echo "Invalid mode: $MODE (use now or stage)" >&2
  exit 1
fi

if ! [[ "$THEME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Invalid theme name: $THEME (letters, digits, '.', '_' and '-' only)" >&2
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/themes/$THEME.json" ]; then
  log "ERROR: themes/$THEME.json does not exist"
  exit 1
fi

if ! is_running; then
  # Nothing running: no race condition is possible, so everything is applied at once,
  # whether "now" or "stage" -- and any old pending change is cleared along the way.
  apply_pending_cfg_if_any
  log "Double Commander is not running. Applying the complete theme '$THEME'..."
  if ! python3 "$SCRIPT_DIR/dc_theme_apply.py" --apply "$THEME" >> "$LOG_FILE" 2>&1; then
    log "ERROR: dc_theme_apply.py failed, see above."
    exit 1
  fi
  log "Theme applied. It will show when Double Commander is opened."
  exit 0
fi

if [ "$MODE" = "stage" ]; then
  log "Stage mode: DC is running. Applying only colors.json of '$THEME' live..."
  if ! python3 "$SCRIPT_DIR/dc_theme_apply.py" --apply "$THEME" --only colors >> "$LOG_FILE" 2>&1; then
    log "ERROR: dc_theme_apply.py failed, see above."
    exit 1
  fi
  echo "$THEME" > "$PENDING_FILE"
  log "colors.json applied. DarkMode in doublecmd.cfg is left pending until the next launch (marker: $PENDING_FILE)."
  log "Done (stage)."
  exit 0
fi

# MODE=now: graceful quit -> apply everything -> reopen.
log "Quitting $DC_APP_NAME (graceful quit)..."
osascript -e "tell application \"$DC_APP_NAME\" to quit" 2>> "$LOG_FILE" || true

for i in $(seq 1 30); do
  if ! is_running; then
    break
  fi
  sleep 0.5
done

if is_running; then
  log "ERROR: $DC_APP_NAME did not quit within 15s, aborting without touching the config (avoiding the race condition)."
  exit 1
fi
log "$DC_APP_NAME closed."

apply_pending_cfg_if_any

log "Applying theme '$THEME'..."
if ! python3 "$SCRIPT_DIR/dc_theme_apply.py" --apply "$THEME" >> "$LOG_FILE" 2>&1; then
  log "ERROR: dc_theme_apply.py failed, see above."
  exit 1
fi
log "Theme applied."

log "Reopening $DC_APP_NAME..."
if ! open -a "$DC_APP_NAME"; then
  log "ERROR: could not reopen $DC_APP_NAME; the theme was already applied, open it manually."
  exit 1
fi

log "Done."
