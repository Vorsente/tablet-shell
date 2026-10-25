#!/bin/bash
# iPadOS look from vinceliuice's WhiteSur themes (GPL-3.0 / MIT), fetched at fixed commits and
# installed for the user, then adjusted for the shell:
#   - WhiteSurLiquid plasma themes: KPlugin Id = directory name (upstream says "WhiteSur", so Plasma
#     cannot tell the variants apart), iPad glass panel and dock (make-glass-panel.py)
#   - icons (WhiteSur, -light, -dark) and the MacTahoe icon theme (macOS 26 style, used by the iPad
#     looks), plus MacTahoe-style icons for the apps it has no icon for (tablet-tools app-icons)
#   - wallpaper packages Sonoma-iPad / Monterey-iPad / Ventura-iPad with light and dark images,
#     which the day/night wallpaper fades between
# Usage: scripts/themes.sh    (re-run safely; downloads go to ~/.cache/tablet-shell)
set -e
HERE="$(dirname "$(readlink -f "$0")")"
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/tablet-shell
SHARE=$HOME/.local/share
KDE_REV=cf4df59ce91004f7ea39358b1b8ff917d5c329f7
ICONS_REV=73d8040da51a9ed74e47c7366e7e9ff437601a5c
WALL_REV=5c1d7ca20b8de0a7efe443792c19e49277262e02
TAHOE_REV=839848b9a8a38a92a6936e30c4abe35cc6f2546d
mkdir -p "$CACHE"

fetch() {   # fetch REPO REV
    local dir="$CACHE/$1"
    if [ ! -d "$dir/.git" ]; then
        git clone -q --filter=blob:none --no-checkout "https://github.com/vinceliuice/$1" "$dir"
    fi
    git -C "$dir" -c advice.detachedHead=false checkout -q "$2" 2>/dev/null || {
        git -C "$dir" fetch -q origin && git -C "$dir" -c advice.detachedHead=false checkout -q "$2"; }
    echo "$dir"
}

echo "  WhiteSur KDE"
src=$(fetch WhiteSur-kde $KDE_REV)
(cd "$src" && ./install.sh >/dev/null)
for d in "$SHARE"/plasma/desktoptheme/WhiteSur*; do
    python3 -I - "$d" <<'PY'
import json, os, sys
d = sys.argv[1]
p = os.path.join(d, "metadata.json")
if os.path.exists(p):
    m = json.load(open(p))
    m.setdefault("KPlugin", {})["Id"] = os.path.basename(d)
    json.dump(m, open(p, "w"), indent=4, ensure_ascii=False)
PY
done
python3 -I "$HERE/make-glass-panel.py" "$SHARE/plasma/desktoptheme" >/dev/null
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}"/plasma_theme_WhiteSurLiquid*

echo "  WhiteSur icons"
if [ ! -f "$SHARE/icons/WhiteSur/index.theme" ] || [ "$(cat "$SHARE/icons/.whitesur-rev" 2>/dev/null)" != $ICONS_REV ]; then
    src=$(fetch WhiteSur-icon-theme $ICONS_REV)
    (cd "$src" && ./install.sh -d "$SHARE/icons" >/dev/null)
    echo $ICONS_REV > "$SHARE/icons/.whitesur-rev"
fi

echo "  MacTahoe icons"
if [ ! -f "$SHARE/icons/MacTahoe/index.theme" ] || [ "$(cat "$SHARE/icons/.mactahoe-rev" 2>/dev/null)" != $TAHOE_REV ]; then
    src=$(fetch MacTahoe-icon-theme $TAHOE_REV)
    (cd "$src" && ./install.sh -d "$SHARE/icons" -t default >/dev/null)
    echo $TAHOE_REV > "$SHARE/icons/.mactahoe-rev"
fi
# apps the theme has no icon for (installing the theme again removed the earlier ones)
[ -x "$HOME/.local/bin/app-icons-refresh" ] && "$HOME/.local/bin/app-icons-refresh" || true

echo "  wallpapers"
src=$(fetch WhiteSur-wallpapers $WALL_REV)
for name in Sonoma Monterey Ventura; do
    pkg="$SHARE/wallpapers/$name-iPad"
    # an existing package is left as it is: a running wallpaper keeps the file it chose
    if [ -n "$(ls -A "$pkg/contents/images" 2>/dev/null)" ] && [ -n "$(ls -A "$pkg/contents/images_dark" 2>/dev/null)" ]; then
        continue
    fi
    mkdir -p "$pkg/contents/images" "$pkg/contents/images_dark"
    for variant in light dark; do
        img="$src/4k/$name-$variant.jpg"
        out="$pkg/contents/images"; [ $variant = dark ] && out="$pkg/contents/images_dark"
        # Plasma picks the image by its WIDTHxHEIGHT file name
        size=$(python3 -I - "$img" <<'PY'
import struct, sys
f = open(sys.argv[1], "rb"); f.read(2)
while True:
    marker, length = struct.unpack(">HH", f.read(4))
    if 0xFFC0 <= marker <= 0xFFCF and marker not in (0xFFC4, 0xFFC8, 0xFFCC):
        f.read(1); h, w = struct.unpack(">HH", f.read(4)); print(f"{w}x{h}"); break
    f.read(length - 2)
PY
)
        rm -f "$out"/*
        cp "$img" "$out/$size.jpg"
    done
    printf '{"KPlugin": {"Id": "%s-iPad", "Name": "%s", "License": "MIT", "Authors": [{"Name": "vinceliuice"}]}}\n' "$name" "$name" > "$pkg/metadata.json"
done
