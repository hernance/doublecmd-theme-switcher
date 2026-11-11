#!/bin/bash
# Boton de toolbar de DC: abre el selector grafico de temas (SwiftUI, picker-ui/) con
# miniatura + nombre por tarjeta. El binario se recompila solo si el fuente cambio.
# Si la compilacion falla (ej. sin toolchain Swift), cae al flujo viejo de osascript.
# El picker (o el fallback) termina disparando dc_theme_phoenix.sh <tema> <now|stage>
# detached, para sobrevivir al quit de DC que el propio flujo puede disparar.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
THEMES_DIR="$SCRIPT_DIR/themes"
LOG_FILE="$SCRIPT_DIR/phoenix.log"
DC_APP_NAME="Double Commander"
SRC="$SCRIPT_DIR/picker-ui/DCThemePicker.swift"
BIN="$SCRIPT_DIR/picker-ui/DCThemePicker"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [picker] $*" >> "$LOG_FILE"; }

# --- UI SwiftUI (camino principal) -------------------------------------------
if [ -f "$SRC" ]; then
  if [ ! -x "$BIN" ] || [ "$SRC" -nt "$BIN" ]; then
    log "Compilando picker SwiftUI..."
    if swiftc -O -parse-as-library -o "$BIN" "$SRC" >> "$LOG_FILE" 2>&1; then
      log "Picker compilado OK."
    else
      log "ERROR: fallo la compilacion del picker SwiftUI; uso el fallback osascript."
      BIN=""
    fi
  fi
  if [ -n "$BIN" ] && [ -x "$BIN" ]; then
    # nohup + disown: la UI no muere si DC (quien lanzo este script) se cierra.
    nohup "$BIN" >> "$LOG_FILE" 2>&1 &
    disown
    exit 0
  fi
fi

# --- Fallback: flujo viejo de osascript (lista de texto + Preview) -----------
log "Usando fallback osascript."

THEMES=()
while IFS= read -r line; do
  # Solo nombres seguros para interpolar en AppleScript mas abajo (sin comillas/`;`/etc).
  [[ "$line" =~ ^[A-Za-z0-9._-]+$ ]] && THEMES+=("$line")
done < <(cd "$THEMES_DIR" && ls *.json 2>/dev/null | sed 's/\.json$//' | sort)

if [ "${#THEMES[@]}" -eq 0 ]; then
  themes_dir_as="${THEMES_DIR//\\/\\\\}"
  themes_dir_as="${themes_dir_as//\"/\\\"}"
  osascript -e "display alert \"DC Theme Picker\" message \"No hay temas en $themes_dir_as\""
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

CHOSEN=$(osascript -e "choose from list {$list_as} with title \"Double Commander\" with prompt \"Elegi un tema:\"" 2>/dev/null || true)

if [ -z "$CHOSEN" ] || [ "$CHOSEN" = "false" ]; then
  exit 0
fi

MODE="now"
if pgrep -f "$DC_APP_NAME" > /dev/null 2>&1; then
  ANSWER=$(osascript -e "display dialog \"Tema '$CHOSEN' elegido. Double Commander esta abierto: para verlo hay que cerrarlo y volver a abrirlo (los tabs se mantienen).\" with title \"Double Commander\" buttons {\"Cancelar\", \"Al proximo inicio\", \"Cerrar y aplicar ahora\"} default button \"Cerrar y aplicar ahora\" cancel button \"Cancelar\"" 2>/dev/null || echo "button returned:Cancelar")
  BUTTON="${ANSWER#button returned:}"
  case "$BUTTON" in
    "Cerrar y aplicar ahora") MODE="now" ;;
    "Al proximo inicio") MODE="stage" ;;
    *) exit 0 ;;
  esac
fi

nohup "$SCRIPT_DIR/dc_theme_phoenix.sh" "$CHOSEN" "$MODE" >> "$LOG_FILE" 2>&1 &
disown
