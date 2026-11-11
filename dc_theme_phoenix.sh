#!/bin/bash
# Cambia el tema de Double Commander. Dos modos:
#   now   - cierra DC con quit gracioso (guarda tabs/estado), aplica el tema completo
#           (colors.json + DarkMode en doublecmd.cfg), y lo reabre si estaba corriendo.
#   stage - si DC esta corriendo: aplica SOLO colors.json en caliente (seguro, DC no
#           lo reescribe nunca) y deja el DarkMode de doublecmd.cfg pendiente en un
#           marker, porque DC si reescribe su propio doublecmd.cfg al cerrar y pisaria
#           el cambio. El pendiente se termina de aplicar solo, sin pedir tema, la
#           proxima vez que este script se invoca con DC ya cerrado (cualquier modo).
#           Si DC NO esta corriendo, "stage" aplica todo de una (no hay nada que pisar).
#
# Uso: dc_theme_phoenix.sh <nombre-tema> [now|stage]   (default: now)

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
  # Solo se llama con DC confirmado no-corriendo. Termina de aplicar el DarkMode
  # que un "stage" anterior dejo pendiente por no poder tocar doublecmd.cfg en caliente.
  if [ -f "$PENDING_FILE" ]; then
    local pending_theme
    pending_theme="$(cat "$PENDING_FILE")"
    log "Pendiente de stage anterior: aplicando DarkMode de '$pending_theme' (doublecmd.cfg)..."
    if python3 "$SCRIPT_DIR/dc_theme_apply.py" --apply "$pending_theme" --only cfg >> "$LOG_FILE" 2>&1; then
      rm -f "$PENDING_FILE"
      log "Pendiente aplicado y limpiado."
    else
      log "ERROR: no se pudo aplicar el pendiente de '$pending_theme', se deja el marker."
    fi
  fi
}

if [ -z "$THEME" ]; then
  echo "Uso: $0 <nombre-tema> [now|stage]" >&2
  exit 1
fi

if [ "$MODE" != "now" ] && [ "$MODE" != "stage" ]; then
  echo "Modo invalido: $MODE (usar now o stage)" >&2
  exit 1
fi

if ! [[ "$THEME" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Nombre de tema invalido: $THEME (solo letras, numeros, '.', '_' y '-')" >&2
  exit 1
fi

if [ ! -f "$SCRIPT_DIR/themes/$THEME.json" ]; then
  log "ERROR: no existe themes/$THEME.json"
  exit 1
fi

if ! is_running; then
  # Nada corriendo: no hay race condition posible, se aplica todo de una,
  # sea "now" o "stage" -- y de paso se limpia cualquier pendiente viejo.
  apply_pending_cfg_if_any
  log "Double Commander no esta corriendo. Aplicando tema '$THEME' completo..."
  if ! python3 "$SCRIPT_DIR/dc_theme_apply.py" --apply "$THEME" >> "$LOG_FILE" 2>&1; then
    log "ERROR: dc_theme_apply.py fallo, ver arriba."
    exit 1
  fi
  log "Tema aplicado. Se vera al abrir Double Commander."
  exit 0
fi

if [ "$MODE" = "stage" ]; then
  log "Modo stage: DC esta corriendo. Aplicando solo colors.json de '$THEME' en caliente..."
  if ! python3 "$SCRIPT_DIR/dc_theme_apply.py" --apply "$THEME" --only colors >> "$LOG_FILE" 2>&1; then
    log "ERROR: dc_theme_apply.py fallo, ver arriba."
    exit 1
  fi
  echo "$THEME" > "$PENDING_FILE"
  log "colors.json aplicado ya. DarkMode de doublecmd.cfg queda pendiente para el proximo inicio (marker: $PENDING_FILE)."
  log "Listo (stage)."
  exit 0
fi

# MODE=now: quit gracioso -> aplicar todo -> reabrir.
log "Cerrando $DC_APP_NAME (quit gracioso)..."
osascript -e "tell application \"$DC_APP_NAME\" to quit" 2>> "$LOG_FILE" || true

for i in $(seq 1 30); do
  if ! is_running; then
    break
  fi
  sleep 0.5
done

if is_running; then
  log "ERROR: $DC_APP_NAME no cerro en 15s, aborto sin tocar config (evito la race condition)."
  exit 1
fi
log "$DC_APP_NAME cerrado."

apply_pending_cfg_if_any

log "Aplicando tema '$THEME'..."
if ! python3 "$SCRIPT_DIR/dc_theme_apply.py" --apply "$THEME" >> "$LOG_FILE" 2>&1; then
  log "ERROR: dc_theme_apply.py fallo, ver arriba."
  exit 1
fi
log "Tema aplicado."

log "Reabriendo $DC_APP_NAME..."
if ! open -a "$DC_APP_NAME"; then
  log "ERROR: no se pudo reabrir $DC_APP_NAME; el tema ya quedo aplicado, abrila a mano."
  exit 1
fi

log "Listo."
