#!/bin/bash
# DC toolbar button: opens the graphical theme picker (SwiftUI, picker-ui/) with a
# thumbnail + name per card. The binary is rebuilt only if the source changed.
# If compilation fails (e.g. no Swift toolchain), it falls back to the old osascript flow.
# The picker (or the fallback) ends up launching dc_theme_phoenix.sh <theme> <now|stage>
# detached, so it survives the DC quit that the flow itself may trigger.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$SCRIPT_DIR/themes"
LOG_FILE="$SCRIPT_DIR/phoenix.log"
DC_APP_NAME="Double Commander"
SRC="$SCRIPT_DIR/picker-ui/DCThemePicker.swift"
BIN="$SCRIPT_DIR/picker-ui/DCThemePicker"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [picker] $*" >> "$LOG_FILE"; }

# --- SwiftUI UI (main path) -------------------------------------------
if [ -f "$SRC" ]; then
  if [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then
    log "Compiling SwiftUI picker..."
    if swiftc -O -parse-as-library -o "$BIN" "$SRC" >> "$LOG_FILE" 2>&1; then
      log "Picker compiled OK."
    else
      log "ERROR: SwiftUI picker compilation failed; using the osascript fallback."
      BIN=""
    fi
  fi
  if [ -n "$BIN" ] && [ -x "$BIN" ]; then
    # nohup + disown: the UI doesn't die if DC (which launched this script) quits.
    nohup "$BIN" >> "$LOG_FILE" 2>&1 &
    disown
    exit 0
  fi
fi

# --- Fallback: old osascript flow (text list + Preview) -----------
log "Using osascript fallback."

THEMES=()
while IFS= read -r line; do
  # Only names that are safe to interpolate into AppleScript below (no quotes/`;`/etc).
  [[ "$line" =~ ^[A-Za-z0-9._-]+$ ]] && THEMES+=("$line")
done < <(cd "$THEMES_DIR" && ls *.json 2>/dev/null | sed 's/\.json$//' | sort)

if [ "${#THEMES[@]}" -eq 0 ]; then
  themes_dir_as="${THEMES_DIR//\\/\\\\}"
  themes_dir_as="${themes_dir_as//\"/\\\"}"
  osascript -e "display alert \"DC Theme Picker\" message \"No themes in $themes_dir_as\""
  exit 1
fi

list_as=""
for t in "${THEMES[@]}"; do
  list_as+="\"$t\", "
done
list_as="${list_as%, }"

shopt -s nullglob
THUMBS=("$THEMES_DIR"/*.thumb.png)
shopt -u nullglob
if [ "${#THUMBS[@]}" -gt 0 ]; then
  open -a Preview "${THUMBS[@]}" 2>/dev/null || true
fi

CHOSEN=$(osascript -e "choose from list {$list_as} with title \"Double Commander\" with prompt \"Choose a theme:\"" 2>/dev/null || true)

if [ -z "$CHOSEN" ] || [ "$CHOSEN" = "false" ]; then
  exit 0
fi

MODE="now"
if pgrep -f "$DC_APP_NAME" > /dev/null 2>&1; then
  ANSWER=$(osascript -e "display dialog \"Theme '$CHOSEN' selected. Double Commander is open: to see it, it has to be closed and reopened (tabs are preserved).\" with title \"Double Commander\" buttons {\"Cancel\", \"On next launch\", \"Quit and apply now\"} default button \"Quit and apply now\" cancel button \"Cancel\"" 2>/dev/null || echo "button returned:Cancel")
  BUTTON="${ANSWER#button returned:}"
  case "$BUTTON" in
    "Quit and apply now") MODE="now" ;;
    "On next launch") MODE="stage" ;;
    *) exit 0 ;;
  esac
fi

nohup "$SCRIPT_DIR/dc_theme_phoenix.sh" "$CHOSEN" "$MODE" >> "$LOG_FILE" 2>&1 &
disown
