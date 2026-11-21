#!/usr/bin/env python3
"""Theme changer for Double Commander, adapted to the external colors.json scheme
(ConfigVersion >= ~14). The original project (delington/Double-Commander-Theme-Changer)
writes <Foreground>/<Background>/<LogWindow>/<PathLabel> directly into doublecmd.xml,
a scheme DC stopped reading once it moved the colors out to colors.json. This script
replaces the matching Style block (e.g. "Dark") inside colors.json
instead of touching the XML.

Usage:
  dc_theme_apply.py --list
  dc_theme_apply.py --apply vscode-2024
  dc_theme_apply.py --apply vscode-2024 --style Dark   # if the json has more than one Style
  dc_theme_apply.py --apply vscode-2024 --with-fonts   # also overwrites <Fonts> in the xml

Themes: <name>.json files (+ optional <name>.cfg with DarkMode=N) in ./themes/,
same format as https://github.com/t0mmili/dc-themes (carpeta schemes/).
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


def atomic_write(path, content):
    """Write to a temp file in the same directory and replace the original with os.replace:
    if the process is interrupted, the file keeps either the old or the new content, never a partial write."""
    tmp_path = f"{path}.tmp-{os.getpid()}"
    with open(tmp_path, "w") as f:
        f.write(content)
        f.flush()
        os.fsync(f.fileno())
    os.replace(tmp_path, path)


def find_style_block(text, name):
    """Return (start, end) of the {"Name": name, ...} object inside a Styles array,
    by walking the brace balance (the file is not strict JSON: keys are unquoted)."""
    marker = f'Name : "{name}"'
    if text.count(marker) != 1:
        raise RuntimeError(
            f"Style '{name}' appears {text.count(marker)} times (expected 1); aborting without writing."
        )
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
            "colors.json would be unbalanced after the replacement; aborting without writing."
        )

    backup_path = backup(colors_path)
    atomic_write(colors_path, new_content)
    return backup_path


def warn(msg):
    print(f"WARNING: {msg}", file=sys.stderr)


def apply_darkmode_cfg(config_dir, theme_cfg_path):
    if not theme_cfg_path or not os.path.isfile(theme_cfg_path):
        warn("the theme has no .cfg; DarkMode will not be applied.")
        return None
    with open(theme_cfg_path) as f:
        cfg_text = f.read()
    m = re.search(r"DarkMode=(\d+)", cfg_text)
    if not m:
        warn("the theme .cfg has no DarkMode; not applying it.")
        return None
    new_val = m.group(1)

    cfg_path = os.path.join(config_dir, "doublecmd.cfg")
    if not os.path.isfile(cfg_path):
        warn(f"{cfg_path} does not exist; DarkMode was not applied.")
        return None
    with open(cfg_path) as f:
        current = f.read()
    updated, n = re.subn(r"DarkMode=\d+", f"DarkMode={new_val}", current, count=1)
    if n == 0:
        warn(f"{cfg_path} has no DarkMode key; not applied.")
        return None
    if updated == current:
        return None
    backup_path = backup(cfg_path)
    atomic_write(cfg_path, updated)
    return backup_path


def apply_fonts_xml(config_dir, theme_json_path_dir_unused):
    """Placeholder: --with-fonts is not implemented for the dc-themes format (the .xml files
    in that repo carry <Fonts>, but we leave it alone by default so as not to overwrite your own fonts)."""
    raise NotImplementedError(
        "--with-fonts: the <Fonts> fragment lives in the theme's .xml (not in colors.json). "
        "It is left alone by default so as not to overwrite your fonts (JetBrains Mono/Monaco). "
        "If you want it, apply it by hand by copying the <Fonts> block from the theme's .xml."
    )


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true", help="list available themes in ./themes")
    ap.add_argument("--apply", metavar="THEME", help="theme name (without .json) in ./themes")
    ap.add_argument("--style", metavar="NAME", help='Style to replace (default: the first one in the theme json, e.g. "Dark")')
    ap.add_argument("--config-dir", default=DEFAULT_CONFIG_DIR, help=f"DC config directory (default: {DEFAULT_CONFIG_DIR})")
    ap.add_argument("--with-fonts", action="store_true", help="also apply the theme's <Fonts> (not implemented, see --help)")
    ap.add_argument("--only", choices=["all", "colors", "cfg"], default="all",
                     help="apply only colors.json, only doublecmd.cfg (DarkMode), or both (default)")
    args = ap.parse_args()
    args.config_dir = os.path.expanduser(args.config_dir)

    if args.list or not args.apply:
        list_themes()
        return

    if not THEME_NAME_RE.match(args.apply):
        print(
            f"Invalid theme name: {args.apply!r} (letters, digits, '.', '_' and '-' only)",
            file=sys.stderr,
        )
        sys.exit(1)

    theme_json_path = os.path.join(THEMES_DIR, f"{args.apply}.json")
    theme_cfg_path = os.path.join(THEMES_DIR, f"{args.apply}.cfg")
    if not os.path.isfile(theme_json_path):
        print(f"{theme_json_path} does not exist", file=sys.stderr)
        sys.exit(1)

    style_name = args.style or detect_style_name(theme_json_path)
    if not style_name:
        print("Could not detect the theme Style; pass --style", file=sys.stderr)
        sys.exit(1)

    if args.with_fonts:
        apply_fonts_xml(args.config_dir, theme_json_path)

    colors_backup = None
    cfg_backup = None
    try:
        if args.only in ("all", "colors"):
            colors_backup = apply_colors_json(args.config_dir, theme_json_path, style_name)
        if args.only in ("all", "cfg"):
            cfg_backup = apply_darkmode_cfg(args.config_dir, theme_cfg_path)
    except (RuntimeError, OSError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    print(f"Theme '{args.apply}' (style: {style_name}, only={args.only}) applied.")
    if colors_backup:
        print(f"Backup colors.json: {colors_backup}")
    if cfg_backup:
        print(f"Backup doublecmd.cfg: {cfg_backup}")
    print("Changes show up when Double Commander is opened (if it is already open, restart it).")


if __name__ == "__main__":
    main()
