#!/usr/bin/env bash
# Download the Material font and Material-designed Colloid icon packs from the official GPLv3 repository.
# Never execute remote code directly; use the checked-out repository's local installer.
set -euo pipefail
base="${XDG_DATA_HOME:-$HOME/.local/share}/icons"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/tablet-shell/Colloid-icon-theme"
mkdir -p "$base" "$(dirname "$cache")"
# Material typography: Roboto Flex (OFL, has Cyrillic; Google Sans Flex has none). The shell QML
# falls back to the default font while it is missing.
fonts="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/tablet-shell"
if [ ! -s "$fonts/RobotoFlex.ttf" ] && [ "${TABLET_SHELL_OFFLINE:-0}" != 1 ]; then
    mkdir -p "$fonts"
    url='https://raw.githubusercontent.com/google/fonts/main/ofl/robotoflex'
    if curl -sfL --max-time 120 -o "$fonts/RobotoFlex.ttf.part" \
            "$url/RobotoFlex%5BGRAD,XOPQ,XTRA,YOPQ,YTAS,YTDE,YTFI,YTLC,YTUC,opsz,slnt,wdth,wght%5D.ttf"; then
        mv "$fonts/RobotoFlex.ttf.part" "$fonts/RobotoFlex.ttf"
        curl -sfL --max-time 30 -o "$fonts/OFL-RobotoFlex.txt" "$url/OFL.txt" || true
        fc-cache -f "$fonts" >/dev/null 2>&1 || true
    else
        rm -f "$fonts/RobotoFlex.ttf.part"
        printf '%s\n' 'Roboto Flex: download failed, Material uses the default font.'
    fi
fi
if [ -f "$base/Colloid/index.theme" ] && [ -f "$base/Colloid-Dark/index.theme" ] &&
   [ -f "$base/Colloid-Light/index.theme" ]; then
    exit 0
fi
if [ "${TABLET_SHELL_OFFLINE:-0}" = 1 ]; then
    printf '%s\n' 'Material icons: offline, leaving existing icons in place.'
    exit 0
fi
if [ ! -d "$cache/.git" ]; then
    git clone -q --depth 1 https://github.com/vinceliuice/Colloid-icon-theme.git "$cache"
else
    git -C "$cache" pull -q --ff-only
fi
# The -d destination does not install any system-wide files. Both variants are installed.
(cd "$cache" && bash ./install.sh -d "$base" -b >/dev/null)
