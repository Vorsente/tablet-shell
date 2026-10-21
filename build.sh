#!/bin/bash
# Builds the shell's C++ programs into build/ (no CMake: one g++ call per program, moc where a file
# has Q_OBJECT). The QML/data directories are compiled in, so build for the place you install to:
#   PREFIX=~/.local/share ./build.sh        (the default; install.sh does this)
set -e
cd "$(dirname "$(readlink -f "$0")")"
PREFIX=${PREFIX:-$HOME/.local/share}
OUT=build
mkdir -p "$OUT"
MOC=/usr/lib/qt6/moc
QTWS=/usr/lib/qt6/qtwaylandscanner
QSB=/usr/lib/qt6/bin/qsb
CXX=${CXX:-g++}
CXXFLAGS=${CXXFLAGS:-"-std=c++20 -O2 -fPIC"}
qt() { pkg-config --cflags --libs "$@"; }
# KF6 ships no .pc files for these
KCONFIG="-I/usr/include/KF6/KConfigCore -I/usr/include/KF6/KConfig -lKF6ConfigCore"
KCMUTILS="-I/usr/include/KF6/KCMUtils -I/usr/include/KF6/KCMUtilsCore -I/usr/include/KF6/KCMUtilsQuick -lKF6KCMUtilsQuick -lKF6KCMUtilsCore"
KCOREADDONS="-I/usr/include/KF6/KCoreAddons -lKF6CoreAddons"

step() { printf '  %-16s' "$1"; }
ok() { echo ok; }

# translations first: Tr.js copies in the QML trees and en.json
python3 -I i18n/build.py "$OUT/en.json" src/tabletshell src/tablet-settings/qml src/tablet-greeter src/tablet-keyboard/qml \
    shell/plasmoids/org.ipad.homescreen/contents/ui shell/plasmoids/org.ipad.dashboard/contents/ui \
    shell/wallpapers/org.ipad.daynight/contents/ui >/dev/null

step tabletd
$MOC src/tabletd/tabletd.cpp -o "$OUT/tabletd.moc"
$CXX $CXXFLAGS -I"$OUT" -Ii18n src/tabletd/tabletd.cpp -o "$OUT/tabletd" $(qt Qt6DBus Qt6Core) $KCONFIG
ok

step tablet-tools
$CXX $CXXFLAGS -Ii18n src/tabletd/tablet-tools.cpp src/tabletd/typewriter.cpp -o "$OUT/tablet-tools" \
    $(qt Qt6Gui Qt6Network Qt6DBus Qt6Core) $KCONFIG
ok

step tabletshell
mkdir -p "$OUT/shell"
$MOC src/tabletshell/main.cpp -o "$OUT/shell/main.moc"
$CXX $CXXFLAGS -I"$OUT/shell" -Ii18n -DSHELL_DIR="\"$PREFIX/tabletshell\"" src/tabletshell/main.cpp -o "$OUT/tabletshell" \
    $(qt Qt6DBus Qt6Quick Qt6Qml Qt6Gui Qt6Core)
ok

step tablet-settings
$MOC src/tablet-settings/backend.h -o "$OUT/moc_backend.cpp"
$CXX $CXXFLAGS -Isrc/tablet-settings -Ii18n -DAPP_DIR="\"$PREFIX/tablet-settings\"" \
    src/tablet-settings/main.cpp src/tablet-settings/backend.cpp "$OUT/moc_backend.cpp" -o "$OUT/tablet-settings" \
    $(qt Qt6Widgets Qt6QuickControls2 Qt6Quick Qt6DBus Qt6Qml Qt6Core) $KCONFIG $KCMUTILS $KCOREADDONS
ok

step tablet-keyboard
# Wayland input-method protocol code, generated for the installed Qt and wayland versions
XML=/usr/share/wayland-protocols/unstable/input-method/input-method-unstable-v1.xml
K="$OUT/keyboard"
mkdir -p "$K"
wayland-scanner client-header "$XML" "$K/wayland-input-method-unstable-v1-client-protocol.h"
wayland-scanner private-code "$XML" "$K/wayland-input-method-unstable-v1-protocol.c"
$QTWS client-header "$XML" > "$K/qwayland-input-method-unstable-v1.h"
$QTWS client-code "$XML" > "$K/qwayland-input-method-unstable-v1.cpp"
$MOC src/tablet-keyboard/main.cpp -o "$K/main.moc"
QTVER=$(pkg-config --modversion Qt6Core)
PRIV="-I/usr/include/qt6/QtWaylandClient/$QTVER -I/usr/include/qt6/QtWaylandClient/$QTVER/QtWaylandClient
      -I/usr/include/qt6/QtWaylandGlobal/$QTVER -I/usr/include/qt6/QtWaylandGlobal
      -I/usr/include/qt6/QtGui/$QTVER -I/usr/include/qt6/QtGui/$QTVER/QtGui
      -I/usr/include/qt6/QtCore/$QTVER -I/usr/include/qt6/QtCore/$QTVER/QtCore"
gcc -O2 -fPIC -c "$K/wayland-input-method-unstable-v1-protocol.c" -o "$K/protocol.o"
$CXX $CXXFLAGS -I"$K" $PRIV -DKEYBOARD_QML_DIR="\"$PREFIX/tablet-keyboard/qml\"" \
    src/tablet-keyboard/main.cpp "$K/qwayland-input-method-unstable-v1.cpp" "$K/protocol.o" -o "$OUT/tablet-keyboard" \
    $(qt Qt6Quick Qt6Qml Qt6Gui Qt6Core Qt6WaylandClient wayland-client)
ok

step tablet-greeter
$MOC src/tablet-greeter/main.cpp -o "$OUT/greeter.moc"
mkdir -p "$OUT/greeter" && cp "$OUT/greeter.moc" "$OUT/greeter/main.moc"
$CXX $CXXFLAGS -I"$OUT/greeter" -Ii18n src/tablet-greeter/main.cpp -o "$OUT/tablet-greeter" \
    $(qt Qt6Quick Qt6Qml Qt6Gui Qt6Network Qt6Core)
ok

step webapp-runner
$CXX $CXXFLAGS -DRUNNER_DIR="\"$PREFIX/webapps/runner\"" src/webapp-runner/main.cpp -o "$OUT/webapp-runner" \
    $(qt Qt6WebEngineQuick Qt6Quick Qt6Qml Qt6Gui Qt6Core)
ok

step shaders
$QSB --glsl "100es,120,150" --hlsl 50 --msl 12 -o "$OUT/weather.frag.qsb" \
    shell/plasmoids/org.ipad.homescreen/contents/ui/shaders/weather.frag
ok

step sounds
mkdir -p "$OUT/sounds/shell" "$OUT/sounds/keyboard"
python3 -I src/tabletshell/sounds/make-sounds.py "$OUT/sounds/shell" >/dev/null
python3 -I src/tablet-keyboard/sounds/make-sounds.py "$OUT/sounds/keyboard" >/dev/null
ok
