#!/bin/bash
# Targeted update for an already installed tablet-shell. Run as the desktop user, without sudo.
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")/.."
if [ "$EUID" -eq 0 ]; then
    echo 'Run this script as the desktop user, without sudo.' >&2
    exit 1
fi
share="$HOME/.local/share"
if [ ! -d "$share/tabletd" ]; then
    echo 'tablet-shell is not installed. Run bash install.sh first.' >&2
    exit 1
fi
for tool in g++ pkg-config /usr/lib/qt6/moc python3 systemctl; do
    command -v "$tool" >/dev/null || { echo "Missing tool: $tool" >&2; exit 1; }
done
pkg-config --exists Qt6DBus Qt6Core || { echo 'Qt 6 development packages are required.' >&2; exit 1; }
# Build before touching the running installation. No archived binaries are reused.
tmp=$(mktemp -d)
was_active=
cleanup() {
    rm -rf "$tmp"
    if [ -n "$was_active" ]; then systemctl --user start tabletd.service || true; fi
}
trap cleanup EXIT
/usr/lib/qt6/moc src/tabletd/tabletd.cpp -o "$tmp/tabletd.moc"
g++ -std=c++20 -O2 -fPIC -I"$tmp" -Ii18n src/tabletd/tabletd.cpp -o "$tmp/tabletd" \
    $(pkg-config --cflags --libs Qt6DBus Qt6Core) \
    -I/usr/include/KF6/KConfigCore -I/usr/include/KF6/KConfig -lKF6ConfigCore
backup="$HOME/.local/state/tablet-shell/backup-$(date +%Y%m%d-%H%M%S)-$$"
mkdir -p "$backup"
rc="$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc"
[ ! -f "$rc" ] || cp -a "$rc" "$backup/"
cp -a "$share/tabletd/tabletd" "$backup/tabletd"
[ ! -d "$share/tablet-mode" ] || cp -a "$share/tablet-mode" "$backup/"
if systemctl --user is-active --quiet tabletd.service; then was_active=1; fi
systemctl --user stop tabletd.service
install -m755 "$tmp/tabletd" "$share/tabletd/tabletd"
mkdir -p "$share/tablet-mode"
install -m644 shell/tablet-mode/*.js "$share/tablet-mode/"
clock="$share/plasma/plasmoids/org.ipad.statusclock"
mkdir -p "$clock/contents/ui"
install -m644 shell/plasmoids/org.ipad.statusclock/metadata.json "$clock/metadata.json"
install -m644 shell/plasmoids/org.ipad.statusclock/contents/ui/main.qml "$clock/contents/ui/main.qml"
data="$share/plasma/plasmoids/org.ipad.homescreen/contents/ui/HomeData.qml"
if [ -f "$data" ]; then
    cp -a "$data" "$backup/HomeData.qml"
    install -m644 shell/plasmoids/org.ipad.homescreen/contents/ui/HomeData.qml "$data"
fi
systemctl --user start tabletd.service
was_active=
echo "Updated. Panel recovery may take 15 seconds. Backup: $backup"
echo 'To load the HomeData optimization, log out and log in again.'
echo 'If panels remain missing, run ./install.sh --containments and restart the Plasma session.'
