#!/bin/bash
# Installs the tablet shell for the current user on Arch Linux + KDE Plasma 6 (Wayland).
#   ./install.sh                 everything for the user (no sudo): build, files, themes, settings
#   ./install.sh --city Berlin   weather city (default: the time zone's city)
#   ./install.sh --no-themes     keep the current themes/icons/wallpapers
#   ./install.sh --no-build      reuse build/ (after an earlier ./build.sh)
#   ./install.sh --containments  only switch the screens to the home screen / dashboard again
# System parts (login screen, device access, snapshots, boot splash, language, Android) are
# separate sudo scripts in system/; the end of the run lists them.
set -e
cd "$(dirname "$(readlink -f "$0")")"
REPO=$PWD
SHARE=$HOME/.local/share
BIN=$HOME/.local/bin
CITY=
THEMES=1
BUILD=1
ONLY_CONTAINMENTS=
while [ $# -gt 0 ]; do
    case "$1" in
        --city) CITY=$2; shift ;;
        --no-themes) THEMES= ;;
        --no-build) BUILD= ;;
        --containments) ONLY_CONTAINMENTS=1 ;;
        -h|--help) sed -n '2,9p' "$0"; exit 0 ;;
        *) echo "unknown option: $1"; exit 1 ;;
    esac
    shift
done
case "$(kreadconfig6 --file plasma-localerc --group Translations --key LANGUAGE 2>/dev/null)${LANG:-}" in ru*) RU=1 ;; *) RU= ;; esac
t() { if [ -n "$RU" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
say() { printf '\n\e[1m== %s\e[0m\n' "$(t "$1" "$2")"; }
die() { printf '\e[31m%s\e[0m\n' "$(t "$1" "$2")"; exit 1; }
kw() { kwriteconfig6 "$@"; }

# ---- screens: home screen on the main one, dashboard on the built-in screen when docked ---------
# A containment's plugin can only be changed while plasmashell is stopped.
containments() {
    local rc=$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc
    [ -f "$rc" ] || return 0
    switch_containments "$rc" --check || return 0     # already right: leave plasmashell alone
    systemctl --user stop plasma-plasmashell.service
    cp -n "$rc" "$rc.before-tablet-shell" 2>/dev/null || true
    switch_containments "$rc"
    systemctl --user start plasma-plasmashell.service
}
# exit status with --check: 0 = something to change
switch_containments() {
    python3 -I - "$@" <<'PY'
import re, sys
p, check = sys.argv[1], "--check" in sys.argv
lines = open(p).read().split("\n")
# desktop containments: [Containments][N] with location 0 (panels have a location)
groups, cur, changed = {}, None, False
for i, l in enumerate(lines):
    m = re.match(r"^\[Containments\]\[(\d+)\]$", l)
    cur = m.group(1) if m else (None if l.startswith("[") else cur)
    if cur and "=" in l:
        k, v = l.split("=", 1)
        groups.setdefault(cur, {})[k] = (i, v)
for cid, g in groups.items():
    if "plugin" not in g or g.get("location", (0, "0"))[1] not in ("0", ""):
        continue
    if g["plugin"][1] in ("org.kde.plasma.folder", "org.kde.desktopcontainment", "org.ipad.homescreen", "org.ipad.dashboard"):
        screen = g.get("lastScreen", (0, "0"))[1]
        want = "org.ipad.homescreen" if screen in ("0", "-1", "") else "org.ipad.dashboard"
        i, _ = g["plugin"]
        if lines[i] != "plugin=" + want:
            changed = True
        lines[i] = "plugin=" + want
        if "wallpaperplugin" in g:
            j, _ = g["wallpaperplugin"]
            changed = changed or lines[j] != "wallpaperplugin=org.ipad.daynight"
            lines[j] = "wallpaperplugin=org.ipad.daynight"
if check:
    sys.exit(0 if changed else 1)
open(p, "w").write("\n".join(lines))
PY
}
if [ -n "$ONLY_CONTAINMENTS" ]; then
    containments
    exit 0
fi

# ---- 1. what this needs ------------------------------------------------------------------------
say "Проверка системы" "Checking the system"
command -v pacman >/dev/null || die "Нужен Arch Linux (pacman)." "Needs Arch Linux (pacman)."
PLASMA=$(plasmashell --version 2>/dev/null | grep -o '[0-9]\+' | head -1)
[ "${PLASMA:-0}" -ge 6 ] || die "Нужна KDE Plasma 6." "Needs KDE Plasma 6."
[ "${XDG_SESSION_TYPE:-}" = wayland ] || echo "  $(t "Внимание: оболочка рассчитана на сеанс Wayland." "Note: the shell is made for a Wayland session.")"
NEED=(base-devel git curl rsync python qt6-base qt6-declarative qt6-wayland qt6-multimedia qt6-multimedia-ffmpeg
      qt6-webengine qt6-shadertools qt6-tools wayland wayland-protocols kirigami kcmutils kconfig kcoreaddons
      plasma-workspace plasma5support plasma-pa plasma-mobile libksysguard ksystemstats layer-shell-qt libkscreen
      spectacle ghostwriter hunspell-en_us librsvg libpulse upower wl-clipboard at-spi2-core inter-font ttf-croscore)
MISSING=()
for p in "${NEED[@]}"; do
    # fonts installed by hand count too
    case $p in
        inter-font) fc-list | grep -q '/Inter' && continue ;;
        ttf-croscore) fc-list | grep -q 'Cousine' && continue ;;
    esac
    pacman -Qq "$p" >/dev/null 2>&1 || pacman -Qqg "$p" >/dev/null 2>&1 || MISSING+=("$p")
done
if [ ${#MISSING[@]} -gt 0 ]; then
    echo "  $(t "Не хватает пакетов:" "Missing packages:") ${MISSING[*]}"
    echo "  sudo pacman -S --needed ${MISSING[*]}"
    sudo pacman -S --needed "${MISSING[@]}" || die "Установите пакеты и запустите снова." "Install the packages and run again."
fi

# ---- 2. build ----------------------------------------------------------------------------------
if [ -n "$BUILD" ] || [ ! -x build/tabletd ]; then
    say "Сборка (на медленном планшете до 10 минут)" "Building (up to 10 minutes on a slow tablet)"
    PREFIX=$SHARE ./build.sh
fi

# ---- 3. files ----------------------------------------------------------------------------------
say "Файлы" "Files"
# SRC DST: DST becomes a copy of SRC (backups *.bak* / *.orig and local state files are kept)
sync_dir() {
    mkdir -p "$2"
    rsync -a --delete --filter='P *.bak*' --filter='P *.orig' --filter='P previous-input-method.txt' "$1/" "$2/"
}
# programs with their QML
sync_dir src/tabletshell "$SHARE/tabletshell"
sync_dir src/tablet-settings "$SHARE/tablet-settings"
sync_dir src/tablet-keyboard "$SHARE/tablet-keyboard"
mkdir -p "$SHARE/tablet-greeter"
rsync -a src/tablet-greeter/ "$SHARE/tablet-greeter/"
mkdir -p "$SHARE/tabletd" "$SHARE/webapps/runner"
install -m755 build/tabletd build/tablet-tools "$SHARE/tabletd/"
install -m755 build/tabletshell "$SHARE/tabletshell/"
install -m755 build/tablet-settings "$SHARE/tablet-settings/"
install -m755 build/tablet-keyboard "$SHARE/tablet-keyboard/"
install -m755 build/tablet-greeter "$SHARE/tablet-greeter/"
install -m755 build/webapp-runner "$SHARE/webapps/runner/"
install -m644 src/webapp-runner/webapp.qml "$SHARE/webapps/runner/"
mkdir -p "$SHARE/tabletshell/sounds" "$SHARE/tablet-keyboard/sounds"
cp build/sounds/shell/*.wav "$SHARE/tabletshell/sounds/"
cp build/sounds/keyboard/*.wav "$SHARE/tablet-keyboard/sounds/"
install -Dm644 build/en.json "$SHARE/tablet-i18n/en.json"
# Plasma: home screen, dashboard, day/night wallpaper, iPad global themes, KWin scripts
for p in shell/plasmoids/*; do sync_dir "$p" "$SHARE/plasma/plasmoids/$(basename "$p")"; done
install -Dm644 build/weather.frag.qsb "$SHARE/plasma/plasmoids/org.ipad.homescreen/contents/ui/shaders/weather.frag.qsb"
sync_dir shell/wallpapers/org.ipad.daynight "$SHARE/plasma/wallpapers/org.ipad.daynight"
for p in shell/look-and-feel/*; do sync_dir "$p" "$SHARE/plasma/look-and-feel/$(basename "$p")"; done
for p in shell/kwin/scripts/*; do sync_dir "$p" "$SHARE/kwin/scripts/$(basename "$p")"; done
sync_dir shell/tablet-mode "$SHARE/tablet-mode"
# commands
mkdir -p "$BIN"
for f in bin/*; do install -m755 "$f" "$BIN/"; done
ln -sf "$SHARE/tabletd/tabletd" "$BIN/tabletd"
ln -sf "$SHARE/tabletshell/tabletshell" "$BIN/tabletshell"
ln -sf "$SHARE/tablet-settings/tablet-settings" "$BIN/tablet-settings"
ln -sf "$SHARE/tablet-keyboard/tablet-keyboard" "$BIN/tablet-keyboard"
ln -sf "$SHARE/webapps/runner/webapp-runner" "$BIN/webapp-runner"
for l in tablet-tools wallpaper webapp-create screentime-apps; do ln -sf "$SHARE/tabletd/tablet-tools" "$BIN/$l"; done
# app entries, data
mkdir -p "$SHARE/applications"
for f in applications/*.desktop; do
    sed "s|@HOME@|$HOME|g" "$f" > "$SHARE/applications/$(basename "$f")"
done
mkdir -p "$SHARE/typewriter/sounds" "$SHARE/ghostwriter/themes"
cp -n data/typewriter/template.md data/typewriter/template.en.md "$SHARE/typewriter/" 2>/dev/null || true
cp data/typewriter/sounds/*.wav "$SHARE/typewriter/sounds/"
cp data/ghostwriter/*.json "$SHARE/ghostwriter/themes/"
# Firefox: touch-friendly preferences, as a marked block in user.js of each profile (own lines stay)
for ini in "$HOME/.mozilla/firefox/profiles.ini" "$HOME/.config/mozilla/firefox/profiles.ini"; do
    [ -f "$ini" ] || continue
    base=$(dirname "$ini")
    sed -n 's/^Path=//p' "$ini" | while read -r prof; do
        case "$prof" in /*) dir=$prof ;; *) dir=$base/$prof ;; esac
        [ -d "$dir" ] || continue
        js=$dir/user.js
        touch "$js"
        sed -i '/^\/\/ tablet-shell begin$/,/^\/\/ tablet-shell end$/d' "$js"
        { echo "// tablet-shell begin"; cat data/firefox/user.js; echo "// tablet-shell end"; } >> "$js"
    done
done
# the system scripts, where the settings app points to them
sync_dir system "$SHARE/tablet-shell/system"
git rev-parse --short HEAD > "$SHARE/tablet-shell/version" 2>/dev/null || true

# ---- 4. themes ---------------------------------------------------------------------------------
if [ -n "$THEMES" ]; then
    say "Темы WhiteSur (загрузка)" "WhiteSur themes (download)"
    scripts/themes.sh
fi

# ---- 5. hardware -------------------------------------------------------------------------------
say "Устройство" "Device"
HW=$("$BIN/tablet-tools" hardware)
echo "  $HW"
# Bay Trail / Cherry Trail graphics: only the old i965 VA-API driver works (iHD fails and slows
# every video start)
if grep -qE 'Atom\(TM\) (x[57]-Z8|CPU Z3[0-9]{3})' /proc/cpuinfo; then
    mkdir -p "$HOME/.config/environment.d"
    printf '# Bay Trail / Cherry Trail GPU: only the i965 VA-API driver works\nLIBVA_DRIVER_NAME=i965\n' > "$HOME/.config/environment.d/libva.conf"
fi

# ---- 6. KDE settings the shell needs -----------------------------------------------------------
say "Настройки KDE" "KDE settings"
# KWin: our scripts, the on-screen keyboard, gestures belong to the shell, hot corner off
for s in tablet-gestures split-view slide-over picture-in-picture dock-mode; do
    kw --file kwinrc --group Plugins --key "${s}Enabled" true
done
kw --file kwinrc --group Plugins --key blurEnabled true
kw --file kwinrc --group Effect-blur --key BlurStrength 4
kw --file kwinrc --group Wayland --key InputMethod "$SHARE/applications/tablet-keyboard.desktop"
for e in Top Bottom Left Right; do kw --file kwinrc --group TouchEdges --key $e None; done
kw --file kwinrc --group ElectricBorders --key TopLeft None
kw --file kwinrc --group Effect-overview --key BorderActivate 9
kw --file kwinrc --group ModifierOnlyShortcuts --key Meta "org.ipad.TabletD,/,org.ipad.TabletD,MetaKey"
kw --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnLeft XIA
kw --file kwinrc --group org.kde.kdecoration2 --key ButtonsOnRight ""
# light/dark iPad themes by time of day, Inter font, a bit faster animations
kw --file kdeglobals --group KDE --key DefaultLightLookAndFeel org.ipad.light
kw --file kdeglobals --group KDE --key DefaultDarkLookAndFeel org.ipad.dark
kw --file kdeglobals --group KDE --key AnimationDurationFactor 0.75
for k in font menuFont toolBarFont; do kw --file kdeglobals --group General --key $k "Inter,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"; done
kw --file kdeglobals --group General --key smallestReadableFont "Inter,8,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
kw --file kdeglobals --group WM --key activeFont "Inter,10,-1,5,600,0,0,0,0,0,0,0,0,0,0,1"
# Plasma Mobile pieces used by the shell: the task switcher (iPhone gestures) and quick settings
kw --file plasmamobilerc --group General --key navigationPanelEnabled false
[ -n "$(kreadconfig6 --file plasmamobilerc --group QuickSettings --key enabledQuickSettings)" ] || \
    kw --file plasmamobilerc --group QuickSettings --key enabledQuickSettings \
    "org.kde.plasma.quicksetting.wifi,org.kde.plasma.quicksetting.bluetooth,org.kde.plasma.quicksetting.airplanemode,org.kde.plasma.quicksetting.donotdisturb,org.kde.plasma.quicksetting.screenrotation,org.kde.plasma.quicksetting.nightcolor,org.kde.plasma.quicksetting.caffeine,org.kde.plasma.quicksetting.keyboardtoggle,org.kde.plasma.quicksetting.screenshot,org.kde.plasma.quicksetting.record,org.kde.plasma.quicksetting.powermenu"
# touch-friendly file manager
kw --file dolphinrc --group IconsMode --key IconSize 96
kw --file dolphinrc --group MainWindow --key MenuBar Disabled
# small devices (4 GB RAM or less): no file indexing, fewer background modules
if [ "$(awk '/MemTotal/{print $2}' /proc/meminfo)" -le 4200000 ]; then
    kw --file baloofilerc --group "Basic Settings" --key Indexing-Enabled false
    for m in appmenu kded_bolt smbwatcher wpad_detector remotenotifier kameleon donationmessage kded_plasma_welcome \
             browserintegrationreminder browserintegrationflatpakintegrator kded_accounts smart plasmavault \
             kded_plasma_mobile_autodetect_apn kded_plasma_mobile_start baloosearchmodule; do
        kw --file kded6rc --group "Module-$m" --key autoload false
    done
fi
# weather and the day/night wallpaper: a city (the time zone's unless given) and its coordinates
if [ -z "$CITY" ]; then
    CITY=$(timedatectl show -p Timezone --value 2>/dev/null | sed 's|.*/||; s|_| |g')
fi
GEO=$(curl -fsS --max-time 10 "https://geocoding-api.open-meteo.com/v1/search?count=1&language=$([ -n "$RU" ] && echo ru || echo en)&name=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1]))' "$CITY")" 2>/dev/null || true)
LAT=$(echo "$GEO" | grep -o '"latitude":[-0-9.]*' | head -1 | cut -d: -f2)
LON=$(echo "$GEO" | grep -o '"longitude":[-0-9.]*' | head -1 | cut -d: -f2)
CITYNAME=$(echo "$GEO" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
[ -n "$CITYNAME" ] && CITY=$CITYNAME
echo "  $(t "Город" "City"): ${CITY:-?} ${LAT:+($LAT, $LON)}"
# the lock screen shows the same wallpaper package
WP=$SHARE/wallpapers/Monterey-iPad
[ -d "$WP" ] || WP=$(ls -d "$SHARE"/wallpapers/*-iPad 2>/dev/null | head -1)
if [ -n "$WP" ] && [ -z "$(kreadconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.ipad.daynight --group General --key Image)" ]; then
    kw --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.ipad.daynight
    kw --file kscreenlockerrc --group Greeter --group Wallpaper --group org.ipad.daynight --group General --key Image "file://$WP/"
fi

# ---- 7. services -------------------------------------------------------------------------------
say "Службы" "Services"
mkdir -p "$HOME/.config/systemd/user"
cp systemd/* "$HOME/.config/systemd/user/"
systemctl --user daemon-reload
"$BIN/taskswitcher-sync" || true
"$BIN/lockscreen-sync" || true
systemctl --user enable tabletd.service tabletshell.service lockscreen-sync.service lockscreen-sync.path \
    taskswitcher-sync.service taskswitcher-sync.path greeter-wallpaper.path greeter-wallpaper.timer >/dev/null 2>&1

# ---- 8. apply ----------------------------------------------------------------------------------
say "Применение" "Applying"
FIRST=
[ "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)" = org.ipad.light ] || \
    [ "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)" = org.ipad.dark ] || FIRST=1
if [ -n "$FIRST" ]; then
    plasma-apply-lookandfeel -a org.ipad.light >/dev/null 2>&1 || true
    kw --file kdeglobals --group KDE --key AutomaticLookAndFeel true
fi
containments
# weather city on the home screen and the dashboard, coordinates for the day/night wallpaper
sleep 8
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
desktops().forEach(function (d) {
    d.currentConfigGroup = ['General'];
    if (!d.readConfig('weatherCity', '')) d.writeConfig('weatherCity', '$CITY');
    if ('$LAT' !== '') {
        d.wallpaperPlugin = 'org.ipad.daynight';
        d.currentConfigGroup = ['Wallpaper', 'org.ipad.daynight', 'General'];
        d.writeConfig('Latitude', $LAT + 0); d.writeConfig('Longitude', $LON + 0);
        if (!d.readConfig('Image', '')) d.writeConfig('Image', 'file://$WP/');
    }
    d.reloadConfig();
});" >/dev/null 2>&1 || true
systemctl --user restart tabletd.service tabletshell.service
pkill -u "$USER" -x tablet-keyboard 2>/dev/null || true    # KWin starts the new one
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true

# ---- 9. what is left -----------------------------------------------------------------------------
say "Готово" "Done"
t "Оболочка установлена. Полностью она включится после выхода из сеанса и входа снова.
Системные части (по желанию, через sudo):" "The shell is installed. Log out and back in for everything to take effect.
System parts (optional, with sudo):"; echo
cat <<EOF
  sudo $SHARE/tablet-shell/system/devices.sh            $(t "доступ к кнопкам, перу, клавиатуре; Rnote" "access to buttons, pen, keyboard; Rnote")
  sudo $SHARE/tablet-shell/system/settings-wrappers.sh  $(t "«Настройки» вместо Параметров системы" "Tablet Settings instead of System Settings")
  sudo $SHARE/tablet-shell/system/greeter.sh            $(t "свой экран входа" "own login screen")
  sudo $SHARE/tablet-shell/system/base.sh               $(t "NetworkManager, Bluetooth, zram, приложения" "NetworkManager, Bluetooth, zram, apps")
  sudo $SHARE/tablet-shell/system/language.sh ru|en     $(t "язык системы" "system language")
  sudo $SHARE/tablet-shell/system/recovery/install.sh   $(t "снимки системы (btrfs + systemd-boot)" "system snapshots (btrfs + systemd-boot)")
  sudo $SHARE/tablet-shell/system/boot-splash/install.sh $(t "заставка загрузки" "boot splash")
  sudo $SHARE/tablet-shell/system/android/install.sh    Android (Waydroid)
EOF
