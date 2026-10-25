#!/usr/bin/env python3
# Pixel icon theme: KDE's icon loader tries the shortened names ("input-touchscreen-symbolic" ->
# "input-touchscreen") in Colloid before it reaches Breeze further down the inheritance chain, so a
# colourful Colloid device or app icon wins and, drawn as a mask (isMask), becomes a solid square.
# Copy the Breeze (or Adwaita) symbolic icon of every "*-symbolic" name the shell's QML uses into
# the symbolic folder of TabletPixel and of its Dark / Light variants when Colloid has no exact
# symbolic icon of that name. The variants need their own copy: their glyphs (notifications,
# battery-full) would otherwise win as shortened names over the base theme's exact icon.
# Usage: pixel-symbolic-icons.py ICONS_DIR QML_DIR...
import filecmp
import os
import re
import shutil
import subprocess
import sys

icons, roots = sys.argv[1], sys.argv[2:]
pixel = os.path.join(icons, "TabletPixel")
if not os.path.isdir(pixel):
    sys.exit(0)
themes = [d for d in (pixel, pixel + "Dark", pixel + "Light") if os.path.isfile(os.path.join(d, "index.theme"))]

def index(theme_dirs):
    names = set()
    for d in theme_dirs:
        for dirpath, _, files in os.walk(d):
            for f in files:
                if f.endswith((".svg", ".png")):
                    names.add(f.rsplit(".", 1)[0])
    return names

own = index([os.path.join(d, sub) for d in themes for sub in ("scalable", "apps")])
breeze = {}
# later sources win: Colloid's own symbolic drawing (the Material look), else Breeze, else Adwaita
# for the few neither has (face-smile)
for base in ("/usr/share/icons/Adwaita", "/usr/share/icons/breeze", os.path.join(icons, "breeze"),
             os.path.join(icons, "Colloid")):
    for dirpath, _, files in os.walk(base):
        size = re.search(r"/(\d+)$", dirpath)
        for f in files:
            if f.endswith("-symbolic.svg"):
                n = f[:-4]
                # a later source replaces an earlier one; within one, the largest drawing wins
                rank = (base, int(size.group(1)) if size else 0)
                if n not in breeze or breeze[n][0][0] != base or rank[1] >= breeze[n][0][1]:
                    breeze[n] = (rank, os.path.join(dirpath, f))

used = set()
pattern = re.compile(r'"([a-z0-9][a-z0-9-]*-symbolic)"')
for root in roots:
    for dirpath, _, files in os.walk(root):
        for f in files:
            if f.endswith((".qml", ".js")) and ".bak" not in f:
                with open(os.path.join(dirpath, f), encoding="utf-8", errors="ignore") as fh:
                    used.update(pattern.findall(fh.read()))

copied = set()
for n in sorted(used):
    if n in own:
        continue
    if n not in breeze:
        print("pixel-symbolic-icons: no symbolic icon for", n, file=sys.stderr)
        continue
    src = breeze[n][1]
    for theme in themes:
        os.makedirs(os.path.join(theme, "symbolic"), exist_ok=True)
        dst = os.path.join(theme, "symbolic", n + ".svg")
        if not os.path.exists(dst) or not filecmp.cmp(dst, os.path.realpath(src), shallow=False):
            shutil.copyfile(os.path.realpath(src), dst)
            copied.add(theme)
if shutil.which("gtk-update-icon-cache"):
    for theme in copied:
        subprocess.run(["gtk-update-icon-cache", "-f", "-q", theme], check=False)
