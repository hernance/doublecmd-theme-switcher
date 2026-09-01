#!/usr/bin/env python3
"""Theme changer para Double Commander adaptado al esquema con colors.json externo
(ConfigVersion >= ~14). El proyecto original (delington/Double-Commander-Theme-Changer)
escribe <Foreground>/<Background>/<LogWindow>/<PathLabel> directo en doublecmd.xml,
esquema que DC dejo de leer cuando externalizo los colores a colors.json. Este script
reemplaza el bloque de Style correspondiente (ej. "Dark") dentro de colors.json,
en vez de tocar el XML.

Uso:
  dc_theme_apply.py --list
  dc_theme_apply.py --apply vscode-2024
  dc_theme_apply.py --apply vscode-2024 --style Dark   # si el json trae mas de un Style
  dc_theme_apply.py --apply vscode-2024 --with-fonts   # tambien pisa <Fonts> del xml

Temas: archivos <nombre>.json (+ opcional <nombre>.cfg con DarkMode=N) en ./themes/,
mismo formato que https://github.com/t0mmili/dc-themes (carpeta schemes/).
"""

import argparse
import os
import re
import shutil
import sys

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
THEMES_DIR = os.path.join(SCRIPT_DIR, "themes")
DEFAULT_CONFIG_DIR = os.path.expanduser("~/Library/Preferences/doublecmd")
THEME_NAME_RE = re.compile(r"^[A-Za-z0-9._-]+$")


def backup(path):
    if not os.path.isfile(path):
        return None
    ts = __import__("time").strftime("%Y%m%d-%H%M%S")
    dst = f"{path}.bak-{ts}"
    shutil.copy2(path, dst)
    return dst


def find_style_block(text, name):
    """Devuelve (start, end) del objeto {"Name": name, ...} dentro de un array Styles,
    caminando el balance de llaves (el archivo no es JSON estricto: claves sin comillas)."""
    marker = f'Name : "{name}"'
    idx = text.index(marker)
    open_idx = text.rindex("{", 0, idx)
    depth = 0
    i = open_idx
    while True:
        c = text[i]
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return open_idx, i + 1
        i += 1


def list_themes():
    names = sorted(
        f[:-5] for f in os.listdir(THEMES_DIR) if f.endswith(".json")
    )
    for n in names:
        style = detect_style_name(os.path.join(THEMES_DIR, f"{n}.json"))
        print(f"{n}  (style: {style})")


def detect_style_name(theme_json_path):
    with open(theme_json_path) as f:
        text = f.read()
    m = re.search(r'Name : "([A-Za-z0-9 _-]+)"', text)
    return m.group(1) if m else None


def apply_colors_json(config_dir, theme_json_path, style_name):
    colors_path = os.path.join(config_dir, "colors.json")
    with open(colors_path) as f:
        current = f.read()
    with open(theme_json_path) as f:
        theme = f.read()

    cur_start, cur_end = find_style_block(current, style_name)
    theme_start, theme_end = find_style_block(theme, style_name)
    new_block = theme[theme_start:theme_end]

    new_content = current[:cur_start] + new_block + current[cur_end:]

    if new_content.count("{") != new_content.count("}") or new_content.count(
        "["
    ) != new_content.count("]"):
        raise RuntimeError(
            "colors.json quedaria desbalanceado tras el reemplazo; abortando sin escribir."
        )

    backup_path = backup(colors_path)
    with open(colors_path, "w") as f:
        f.write(new_content)
    return backup_path


def apply_darkmode_cfg(config_dir, theme_cfg_path):
    if not theme_cfg_path or not os.path.isfile(theme_cfg_path):
        return None
    with open(theme_cfg_path) as f:
        cfg_text = f.read()
    m = re.search(r"DarkMode=(\d+)", cfg_text)
    if not m:
        return None
    new_val = m.group(1)

    cfg_path = os.path.join(config_dir, "doublecmd.cfg")
    if not os.path.isfile(cfg_path):
        return None
    with open(cfg_path) as f:
        current = f.read()
    updated = re.sub(r"DarkMode=\d+", f"DarkMode={new_val}", current)
    if updated == current:
        return None
    backup_path = backup(cfg_path)
    with open(cfg_path, "w") as f:
        f.write(updated)
    return backup_path


def apply_fonts_xml(config_dir, theme_json_path_dir_unused):
    """Placeholder: --with-fonts no implementado para el formato dc-themes (los .xml de
    ese repo traen <Fonts> pero no lo tocamos por defecto para no pisar fuentes propias)."""
    raise NotImplementedError(
        "--with-fonts: el fragmento <Fonts> vive en el .xml del tema (no en colors.json). "
        "No se toca por defecto para no pisar tus fuentes (JetBrains Mono/Monaco). "
        "Si lo queres, aplicalo a mano copiando el bloque <Fonts> del .xml del tema."
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true", help="listar temas disponibles en ./themes")
    ap.add_argument("--apply", metavar="TEMA", help="nombre de tema (sin .json) en ./themes")
    ap.add_argument("--style", metavar="NOMBRE", help='Style a reemplazar (por defecto: el primero del json del tema, ej "Dark")')
    ap.add_argument("--config-dir", default=DEFAULT_CONFIG_DIR, help=f"carpeta de config de DC (default: {DEFAULT_CONFIG_DIR})")
    ap.add_argument("--with-fonts", action="store_true", help="tambien aplicar <Fonts> del tema (no implementado, ver --help)")
    ap.add_argument("--only", choices=["all", "colors", "cfg"], default="all",
                     help="aplicar solo colors.json, solo doublecmd.cfg (DarkMode), o ambos (default)")
    args = ap.parse_args()

    if args.list or not args.apply:
        list_themes()
        return

    if not THEME_NAME_RE.match(args.apply):
        print(
            f"Nombre de tema invalido: {args.apply!r} (solo letras, numeros, '.', '_' y '-')",
            file=sys.stderr,
        )
        sys.exit(1)

    theme_json_path = os.path.join(THEMES_DIR, f"{args.apply}.json")
    theme_cfg_path = os.path.join(THEMES_DIR, f"{args.apply}.cfg")
    if not os.path.isfile(theme_json_path):
        print(f"No existe {theme_json_path}", file=sys.stderr)
        sys.exit(1)

    style_name = args.style or detect_style_name(theme_json_path)
    if not style_name:
        print("No se pudo detectar el Style del tema; pasa --style", file=sys.stderr)
        sys.exit(1)

    if args.with_fonts:
        apply_fonts_xml(args.config_dir, theme_json_path)

    colors_backup = None
    cfg_backup = None
    if args.only in ("all", "colors"):
        colors_backup = apply_colors_json(args.config_dir, theme_json_path, style_name)
    if args.only in ("all", "cfg"):
        cfg_backup = apply_darkmode_cfg(args.config_dir, theme_cfg_path)

    print(f"Tema '{args.apply}' (style: {style_name}, only={args.only}) aplicado.")
    if colors_backup:
        print(f"Backup colors.json: {colors_backup}")
    if cfg_backup:
        print(f"Backup doublecmd.cfg: {cfg_backup}")
    print("Reabri Double Commander para ver los cambios.")


if __name__ == "__main__":
    main()
