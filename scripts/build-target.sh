#!/usr/bin/env bash
# Build one tablet-shell artifact; failures are isolated by build.sh.
# Never install from this script: the updater decides which artifacts may replace installed ones.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
name=${1:?missing build target}
OUT=build
PREFIX=${PREFIX:-$HOME/.local/share}
# tool and header locations differ between distributions
source ./scripts/toolchain.sh
if [[ -z "${CXX:-}" ]] && command -v ccache >/dev/null 2>&1; then CXX='ccache g++'; fi
CXX=${CXX:-g++}
read -r -a CXX_CMD <<< "$CXX"
read -r -a FLAGS <<< "${CXXFLAGS:--std=c++20 -O2 -fPIC}"
mkdir -p "$OUT"
qt_flags() {
  local output=$1; shift
  pkg-config --exists "$@" || { echo "Missing Qt packages for $name: $*" >&2; return 1; }
  pkg-config --cflags --libs "$@" | xargs -r -n 100 printf '%s\n' > "$output"
}
# Qt flags are passed as argv, not shell source; this also handles spaces in paths.
qt_args() {
  local -n ref=$1; shift
  local raw
  raw=$(pkg-config --cflags --libs "$@") || return 1
  read -r -a ref <<< "$raw"
}
ui_moc() { "$MOC" src/common/ui-style.h -o "$OUT/moc_ui_style.cpp"; }
case "$name" in
 translations)
  # Translation generation writes Tr.js in-place. Do not modify the keyboard or
  # greeter trees at all in the regular update pipeline.
  dirs=(src/tabletshell src/tablet-settings/qml)
  if [[ "${TABLET_SHELL_EXCLUDE_INPUT_LOCK:-0}" != 1 ]]; then
      dirs+=(src/tablet-greeter src/tablet-keyboard/qml)
  fi
  dirs+=(shell/plasmoids/org.ipad.homescreen/contents/ui shell/plasmoids/org.ipad.dashboard/contents/ui
         shell/wallpapers/org.ipad.daynight/contents/ui)
  python3 -I i18n/build.py "$OUT/en.json" "${dirs[@]}" >/dev/null
  # Material You colour helper: the same copy next to every QML tree that imports it
  for d in "${dirs[@]}"; do
      [[ -f "$d/MaterialYou.js" ]] && ! cmp -s scripts/MaterialYou.js "$d/MaterialYou.js" && cp scripts/MaterialYou.js "$d/MaterialYou.js" || true
  done
  ;;
 tabletd)
  "$MOC" src/tabletd/tabletd.cpp -o "$OUT/tabletd.moc"
  qt_args qt Qt6DBus Qt6Core
  "${CXX_CMD[@]}" "${FLAGS[@]}" -I"$OUT" -Ii18n src/tabletd/tabletd.cpp -o "$OUT/tabletd" "${qt[@]}" "${KCONFIG[@]}"
  ;;
 tablet-tools)
  qt_args qt Qt6Gui Qt6Network Qt6DBus Qt6Core
  "${CXX_CMD[@]}" "${FLAGS[@]}" -Ii18n src/tabletd/tablet-tools.cpp src/tabletd/typewriter.cpp src/tabletd/icons.cpp src/tabletd/material-you.cpp -o "$OUT/tablet-tools" "${qt[@]}" "${KCONFIG[@]}"
  ;;
 tabletshell)
  ui_moc
  mkdir -p "$OUT/shell"
  "$MOC" src/tabletshell/main.cpp -o "$OUT/shell/main.moc"
  qt_args qt Qt6DBus Qt6Quick Qt6Qml Qt6Gui Qt6Core
  "${CXX_CMD[@]}" "${FLAGS[@]}" -I"$OUT/shell" -Ii18n -DSHELL_DIR="\"$PREFIX/tabletshell\"" \
    src/tabletshell/main.cpp "$OUT/moc_ui_style.cpp" -o "$OUT/tabletshell" "${qt[@]}" "${KWINDOWSYSTEM[@]}"
  ;;
 tablet-settings)
  ui_moc
  "$MOC" src/tablet-settings/backend.h -o "$OUT/moc_backend.cpp"
  qt_args qt Qt6Widgets Qt6QuickControls2 Qt6Quick Qt6DBus Qt6Qml Qt6Core
  "${CXX_CMD[@]}" "${FLAGS[@]}" -Isrc/tablet-settings -Ii18n -DAPP_DIR="\"$PREFIX/tablet-settings\"" \
    src/tablet-settings/main.cpp src/tablet-settings/backend.cpp "$OUT/moc_backend.cpp" "$OUT/moc_ui_style.cpp" \
    -o "$OUT/tablet-settings" "${qt[@]}" "${KCONFIG[@]}" "${KCMUTILS[@]}" "${KCOREADDONS[@]}"
  ;;
 tablet-keyboard)
  ui_moc
  OUT="$OUT" PREFIX="$PREFIX" CXX="$CXX" CXXFLAGS="${CXXFLAGS:--std=c++20 -O2 -fPIC}" \
    bash ./scripts/build-keyboard.sh
  ;;
 tablet-greeter)
  "$MOC" src/tablet-greeter/main.cpp -o "$OUT/greeter.moc"
  mkdir -p "$OUT/greeter"
  cp "$OUT/greeter.moc" "$OUT/greeter/main.moc"
  qt_args qt Qt6Quick Qt6Qml Qt6Gui Qt6Network Qt6Core
  "${CXX_CMD[@]}" "${FLAGS[@]}" -I"$OUT/greeter" -Ii18n src/tablet-greeter/main.cpp -o "$OUT/tablet-greeter" "${qt[@]}"
  ;;
 webapp-runner)
  qt_args qt Qt6WebEngineQuick Qt6Quick Qt6Qml Qt6Gui Qt6Core
  "${CXX_CMD[@]}" "${FLAGS[@]}" -DRUNNER_DIR="\"$PREFIX/webapps/runner\"" \
    src/webapp-runner/main.cpp -o "$OUT/webapp-runner" "${qt[@]}"
  ;;
 shaders)
  "$QSB" --glsl '100es,120,150' --hlsl 50 --msl 12 -o "$OUT/weather.frag.qsb" \
    shell/plasmoids/org.ipad.homescreen/contents/ui/shaders/weather.frag
  "$QSB" --glsl '100es,120,150' --hlsl 50 --msl 12 -o "$OUT/themed-icon.frag.qsb" \
    shell/plasmoids/org.ipad.homescreen/contents/ui/shaders/themed-icon.frag
  ;;
 sounds-shell)
  mkdir -p "$OUT/sounds/shell"
  python3 -I src/tabletshell/sounds/make-sounds.py "$OUT/sounds/shell" >/dev/null
  ;;
 sounds-keyboard)
  mkdir -p "$OUT/sounds/keyboard"
  python3 -I src/tablet-keyboard/sounds/make-sounds.py "$OUT/sounds/keyboard" >/dev/null
  ;;
 *) echo "Unknown build target: $name" >&2; exit 2 ;;
esac
