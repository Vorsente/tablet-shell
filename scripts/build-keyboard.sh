#!/usr/bin/env bash
# Build the Qt/Wayland input-method component in isolation, keeping build/tablet-keyboard
# untouched until the complete new executable is successfully linked.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
OUT=${OUT:-build}
PREFIX=${PREFIX:-$HOME/.local/share}
source ./scripts/toolchain.sh
CXX=${CXX:-g++}
read -r -a CXX_CMD <<< "$CXX"
CXXFLAGS=${CXXFLAGS:-'-std=c++20 -O2 -fPIC'}
XML=/usr/share/wayland-protocols/unstable/input-method/input-method-unstable-v1.xml
K="$OUT/keyboard"
mkdir -p "$K"
for tool in gcc wayland-scanner "$QTWS"; do
    command -v "$tool" >/dev/null || { echo "Missing keyboard build tool: $tool" >&2; exit 1; }
done
pkg-config --exists Qt6WaylandClient wayland-client || { echo "Qt Wayland client development files are missing" >&2; exit 1; }

# Never leave an older build artifact that could be mistakenly installed after a failure.
# Keep the last installed executable intact: install.sh deals with it independently.
rm -f "$OUT/tablet-keyboard"
[[ -r "$XML" ]] || { echo "Missing input-method Wayland protocol: $XML" >&2; exit 1; }

wayland-scanner client-header "$XML" "$K/wayland-input-method-unstable-v1-client-protocol.h"
wayland-scanner private-code "$XML" "$K/wayland-input-method-unstable-v1-protocol.c"
"$QTWS" client-header "$XML" > "$K/qwayland-input-method-unstable-v1.h"
"$QTWS" client-code "$XML" > "$K/qwayland-input-method-unstable-v1.cpp"
"$MOC" src/tablet-keyboard/main.cpp -o "$K/main.moc"

# Distribution updates may move Qt private headers. Resolve them by the installed
# module headers rather than assuming the WaylandClient versioned path exists.
QTVER=$(pkg-config --modversion Qt6WaylandClient)
QTINCLUDE=$(pkg-config --variable=includedir Qt6WaylandClient)
[[ -n "$QTINCLUDE" ]] || { echo 'Qt6WaylandClient include directory is unknown' >&2; exit 1; }
QTROOT="$QTINCLUDE/qt6"
[[ -d "$QTROOT" ]] || QTROOT="$QTINCLUDE"
PRIV=()
for module in QtWaylandClient QtWaylandGlobal QtGui QtCore; do
    module_dir="$QTROOT/$module"
    [[ -d "$module_dir" ]] || continue
    # Keep the actual Qt version first, then discover compatible installed roots.
    candidates=("$module_dir/$QTVER")
    for candidate in "$module_dir"/[0-9]*; do
        [[ -d "$candidate" ]] || continue
        candidates+=("$candidate")
    done
    for base in "${candidates[@]}"; do
        [[ -d "$base" ]] || continue
        PRIV+=("-I$base")
        [[ ! -d "$base/$module" ]] || PRIV+=("-I$base/$module")
    done
done
if [[ ! -f "$QTROOT/QtWaylandClient/$QTVER/QtWaylandClient/private/qwaylandwindow_p.h" ]]; then
    echo "Qt Wayland private headers are missing for the installed Qt version $QTVER." >&2
    echo "Run: $(pkg_hint qt6-base qt6-wayland)" >&2
    echo 'Do not mix Qt minor versions (partial system updates are not supported).' >&2
    exit 1
fi

# The preprocessor needs generated protocol headers in addition to Qt's private headers.
gcc -O2 -fPIC "${WAYLAND_CFLAGS[@]}" -c "$K/wayland-input-method-unstable-v1-protocol.c" -o "$K/protocol.o"
# CXXFLAGS is intentionally split, as in the project's normal compiler configuration.
# shellcheck disable=SC2086
"${CXX_CMD[@]}" $CXXFLAGS -I"$K" "${PRIV[@]}" "${WAYLAND_CFLAGS[@]}" "${XKB_CFLAGS[@]}" -DKEYBOARD_QML_DIR="\"$PREFIX/tablet-keyboard/qml\"" \
    src/tablet-keyboard/main.cpp "$OUT/moc_ui_style.cpp" "$K/qwayland-input-method-unstable-v1.cpp" "$K/protocol.o" \
    -o "$K/tablet-keyboard.new" \
    $(pkg-config --cflags --libs Qt6Quick Qt6Qml Qt6Gui Qt6Core Qt6WaylandClient wayland-client)
[[ -s "$K/tablet-keyboard.new" ]] || { echo 'Keyboard build produced an empty executable.' >&2; exit 1; }
mv -f "$K/tablet-keyboard.new" "$OUT/tablet-keyboard"
