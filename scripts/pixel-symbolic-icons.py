#!/usr/bin/env python3
# Pixel icon theme: KDE's icon loader tries the shortened names ("input-touchscreen-symbolic" ->
# "input-touchscreen") in Colloid before it reaches Breeze further down the inheritance chain, so a
# colourful Colloid device or app icon wins and, drawn as a mask (isMask), becomes a solid square.
# Copy the Breeze symbolic icon of every "*-symbolic" name the shell's QML uses into
# TabletPixel/symbolic when Colloid has no exact symbolic icon of that name.
# Usage: pixel-symbolic-icons.py ICONS_DIR QML_DIR...
import os
import re
import shutil
import subprocess
import sys

icons, roots = sys.argv[1], sys.argv[2:]
pixel = os.path.join(icons, "TabletPixel")
target = os.path.join(pixel, "symbolic")
if not os.path.isdir(pixel):
    sys.exit(0)

def index(theme_dirs):
    names = set()
    for d in theme_dirs:
        for dirpath, _, files in os.walk(d):
            for f in files:
                if f.endswith((".svg", ".png")):
                    names.add(f.rsplit(".", 1)[0])
    return names

colloid = index([os.path.join(icons, t) for t in ("Colloid", "Colloid-Dark", "Colloid-Light")]
                + [os.path.join(pixel, d) for d in ("scalable", "apps")])
breeze = {}
for base in ("/usr/share/icons/breeze", os.path.join(icons, "breeze")):
    for dirpath, _, files in os.walk(base):
        size = re.search(r"/(\d+)$", dirpath)
        for f in files:
            if f.endswith("-symbolic.svg"):
                n = f[:-4]
                # prefer the largest drawing (24 over 16)
                if n not in breeze or (size and int(size.group(1)) >= breeze[n][0]):
                    breeze[n] = (int(size.group(1)) if size else 0, os.path.join(dirpath, f))

used = set()
pattern = re.compile(r'"([a-z0-9][a-z0-9-]*-symbolic)"')
for root in roots:
    for dirpath, _, files in os.walk(root):
        for f in files:
            if f.endswith((".qml", ".js")) and ".bak" not in f:
                with open(os.path.join(dirpath, f), encoding="utf-8", errors="ignore") as fh:
                    used.update(pattern.findall(fh.read()))

os.makedirs(target, exist_ok=True)
copied = 0
for n in sorted(used):
    if n in colloid or n not in breeze:
        continue
    dst = os.path.join(target, n + ".svg")
    src = breeze[n][1]
    if not os.path.exists(dst) or os.path.getmtime(dst) < os.path.getmtime(src):
        shutil.copyfile(os.path.realpath(src), dst)
        copied += 1
if copied and shutil.which("gtk-update-icon-cache"):
    subprocess.run(["gtk-update-icon-cache", "-f", "-q", pixel], check=False)
