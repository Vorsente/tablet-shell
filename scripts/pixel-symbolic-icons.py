#!/usr/bin/env python3
# Pixel icon theme: KDE's icon loader tries the shortened names ("input-touchscreen-symbolic" ->
# "input-touchscreen") in Colloid before it reaches Breeze further down the inheritance chain, so a
# colourful Colloid device or app icon wins and, drawn as a mask (isMask), becomes a solid square.
# Copy a symbolic icon for every "*-symbolic" name the shell's QML uses into the symbolic folder of
# TabletPixel and of its Dark / Light variants. The variants need their own copy: their glyphs
# (notifications, battery-full) would otherwise win as shortened names over the base theme's exact
# icon. Each variant copies from sources of its own brightness: a light-theme icon in the dark
# theme made the panel's volume, network and brightness symbols dark on the dark panel.
# Usage: pixel-symbolic-icons.py ICONS_DIR QML_DIR...
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

# Where each theme takes its copies from; a later source wins. Colloid of the same brightness
# first (its icons carry their own colour: #dedede dark, #363636 light), else Breeze (recoloured by
# Plasma through its colour-scheme stylesheet: the themes set FollowsColorScheme), else Adwaita for
# the few neither has (face-smile), its grey turned into the theme's colour.
def sources(theme):
    variant = "Dark" if theme.endswith("Dark") else "Light" if theme.endswith("Light") else ""
    breeze = "breeze-dark" if variant == "Dark" else "breeze"
    return ["/usr/share/icons/Adwaita", "/usr/share/icons/" + breeze, os.path.join(icons, breeze),
            os.path.join(icons, "Colloid-" + variant if variant else "Colloid")]
INK = {"Dark": "#dedede", "Light": "#363636", "": "#363636"}

found = {}
def symbolic(theme):
    """name -> (base, path) of every *-symbolic.svg the theme's sources have"""
    out = {}
    for base in sources(theme):
        if base not in found:
            m = {}
            # Colloid's folders are links into its other variants: follow them
            for dirpath, _, files in os.walk(base, followlinks=True):
                size = re.search(r"/(\d+)$", dirpath)
                for f in files:
                    if f.endswith("-symbolic.svg"):
                        n = f[:-4]
                        s = int(size.group(1)) if size else 0
                        if n not in m or s >= m[n][0]:      # the largest drawing (24 over 16)
                            m[n] = (s, os.path.join(dirpath, f))
            found[base] = m
        for n, (_, path) in found[base].items():
            out[n] = (base, path)
    return out

used = set()
pattern = re.compile(r'"([a-z0-9][a-z0-9-]*-symbolic)"')
for root in roots:
    for dirpath, _, files in os.walk(root):
        for f in files:
            if f.endswith((".qml", ".js")) and ".bak" not in f:
                with open(os.path.join(dirpath, f), encoding="utf-8", errors="ignore") as fh:
                    used.update(pattern.findall(fh.read()))

copied = set()
for theme in themes:
    variant = "Dark" if theme.endswith("Dark") else "Light" if theme.endswith("Light") else ""
    have = symbolic(theme)
    folder = os.path.join(theme, "symbolic")
    os.makedirs(folder, exist_ok=True)
    for n in sorted(used):
        if n in own:
            continue
        if n not in have:
            if theme == pixel:
                print("pixel-symbolic-icons: no symbolic icon for", n, file=sys.stderr)
            continue
        base, src = have[n]
        with open(os.path.realpath(src), encoding="utf-8", errors="ignore") as fh:
            svg = fh.read()
        if "Adwaita" in base:
            svg = re.sub(r'#(?:474747|2e3436|222222|241f31)', INK[variant], svg, flags=re.I)
        dst = os.path.join(folder, n + ".svg")
        try:
            with open(dst, encoding="utf-8", errors="ignore") as fh:
                if fh.read() == svg:
                    continue
        except OSError:
            pass
        with open(dst, "w", encoding="utf-8") as fh:
            fh.write(svg)
        copied.add(theme)
if shutil.which("gtk-update-icon-cache"):
    for theme in copied:
        subprocess.run(["gtk-update-icon-cache", "-f", "-q", theme], check=False)
