#!/bin/bash
# Installs the tablet shell for the current user on KDE Plasma 6 (Wayland): Arch, Debian/Ubuntu,
# Fedora, openSUSE (packages through pacman/apt/dnf/zypper; other distributions: install them by hand).
#   ./install.sh                 asks for sudo once, then: packages, build, files, themes, settings
#                                and the system parts (device access, login screen, network, language,
#                                snapshots, boot splash)
#   ./install.sh --city Berlin   weather city (default: the time zone's city)
#   ./install.sh --no-themes     keep the current themes/icons/wallpapers
#   ./install.sh --update-only  update installed files/services without resetting KDE settings
#   ./install.sh --no-build      reuse build/ (after an earlier ./build.sh)
#   ./install.sh --containments  only switch the screens to the home screen / dashboard again
#   ./install.sh --no-greeter-update  skip refreshing an installed tablet-shell login screen
#   ./install.sh --no-system     no sudo: user part only (the end of the run lists the system scripts)
#   ./install.sh --no-greeter    keep the current login screen (SDDM / Plasma Login)
#   ./install.sh --android       also Android apps (Waydroid; downloads about 1 GB)
# The system parts are the sudo scripts in system/; each can also be run (or undone) on its own.
set -e
cd "$(dirname "$(readlink -f "$0")")"
REPO=$PWD
SHARE=$HOME/.local/share
BIN=$HOME/.local/bin
CITY=
THEMES=1
BUILD=1
ONLY_CONTAINMENTS=
GREETER_UPDATE=1
GREETER_INSTALL=
UPDATE_ONLY=
SYSTEM=1
GREETER=1
ANDROID=
PROTECT_INPUT_LOCK=
SKIP_FAILED_BUILDS=${TABLET_SHELL_SKIP_FAILED_BUILDS:-0}
while [ $# -gt 0 ]; do
    case "$1" in
        --city)
            [ "$#" -ge 2 ] && [ -n "$2" ] && [[ "$2" != --* ]] || { echo "--city requires a city name" >&2; exit 1; }
            CITY=$2; shift ;;
        --no-themes) THEMES= ;;
        --no-build) BUILD= ;;
        --containments) ONLY_CONTAINMENTS=1 ;;
        --no-greeter-update) GREETER_UPDATE= ;;
        --install-greeter) GREETER_INSTALL=1 ;;
        --no-system) SYSTEM= ;;
        --no-greeter) GREETER= ;;
        --android) ANDROID=1 ;;
        --update-only) UPDATE_ONLY=1; PROTECT_INPUT_LOCK=1; GREETER_UPDATE=; THEMES= ;;
        --skip-failed-builds) SKIP_FAILED_BUILDS=1 ;;
        --require-all) SKIP_FAILED_BUILDS=0 ;;
        -h|--help) sed -n '2,16p' "$0"; exit 0 ;;
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
if [ -n "$UPDATE_ONLY" ] && [ -n "$GREETER_INSTALL" ]; then
    die "Нельзя устанавливать экран входа в режиме обновления." "Cannot install a new login manager in update-only mode."
fi
if [ -n "$ONLY_CONTAINMENTS" ]; then
    containments
    exit 0
fi

# ---- 0. administrator rights -------------------------------------------------------------------
# Asked once, before anything is installed: the packages and every system part (system/*.sh) need
# it. sudo's timestamp is kept fresh in the background until the installer exits, so a long build
# does not ask again. Without a terminal (the Settings updater) only an already valid sudo is used.
SUDO_OK=
if [ -n "$SYSTEM" ]; then
    if sudo -n true 2>/dev/null; then
        SUDO_OK=1
    elif [ -t 0 ]; then
        say "Права администратора" "Administrator rights"
        echo "  $(t "Пароль нужен один раз: пакеты, доступ к кнопкам, перу и сенсорному экрану, экран входа, сеть, язык, снимки системы, заставка загрузки." \
                    "The password is asked once: packages, access to buttons, pen and touch screen, login screen, network, language, system snapshots, boot splash.")"
        if sudo -v; then
            SUDO_OK=1
        else
            echo "  $(t "Без sudo: системные части пропущены." "No sudo: the system parts are skipped.")"
        fi
    fi
    if [ -n "$SUDO_OK" ]; then
        ( while kill -0 $$ 2>/dev/null; do sudo -n -v 2>/dev/null; sleep 50; done ) &
        SUDO_KEEPER=$!
        trap 'kill "$SUDO_KEEPER" 2>/dev/null' EXIT
    fi
fi

# ---- 1. what this needs ------------------------------------------------------------------------
say "Проверка системы" "Checking the system"
source "$REPO/system/pkg.sh"
[ -n "$PM" ] || echo "  $(t "Неизвестный менеджер пакетов: зависимости проверьте сами (список в README)." "Unknown package manager: check the dependencies yourself (list in the README).")"
PLASMA=$(plasmashell --version 2>/dev/null | grep -o '[0-9]\+' | head -1)
[ "${PLASMA:-0}" -ge 6 ] || die "Нужна KDE Plasma 6." "Needs KDE Plasma 6."
[ "${XDG_SESSION_TYPE:-}" = wayland ] || echo "  $(t "Внимание: оболочка рассчитана на сеанс Wayland." "Note: the shell is made for a Wayland session.")"
NEED=(base-devel git curl rsync python qt6-base qt6-declarative qt6-wayland qt6-multimedia qt6-multimedia-ffmpeg
      qt6-webengine qt6-shadertools qt6-tools wayland wayland-protocols kirigami kcmutils kconfig kcoreaddons kwindowsystem
      plasma-workspace plasma5support plasma-pa plasma-mobile libksysguard ksystemstats layer-shell-qt libkscreen
      spectacle ghostwriter krita power-profiles-daemon neovim konsole ripgrep fd fzf lazygit tree-sitter-cli ttf-jetbrains-mono-nerd hunspell-en_us librsvg libpulse upower wl-clipboard at-spi2-core inter-font ttf-croscore)
MISSING=()
for p in "${NEED[@]}"; do
    # fonts installed by hand count too
    case $p in
        inter-font) fc-list | grep -q '/Inter' && continue ;;
        ttf-croscore) fc-list | grep -q 'Cousine' && continue ;;
        ttf-jetbrains-mono-nerd) fc-list | grep -q 'JetBrains' && continue ;;
    esac
    [ -z "$PM" ] || pkg_have "$p" || MISSING+=("$p")
done
if [ ${#MISSING[@]} -gt 0 ]; then
    NATIVE=$(pkg_missing "${MISSING[@]}" | tr '\n' ' ')
    echo "  $(t "Не хватает пакетов:" "Missing packages:") $NATIVE"
    echo "  sudo $(pkg_cmd $NATIVE)"
    # Not fatal: names differ between distributions and many packages are only needed at run time
    # (apps, fonts). What the build really needs, the build reports by name and stops there.
    if [ -z "$SUDO_OK" ] && [ ! -t 0 ]; then
        echo "  $(t "Нет sudo без терминала: пакеты не ставлю, поставьте командой выше." "No sudo without a terminal: packages not installed, use the command above.")" >&2
    elif ! pkg_install --sudo "${MISSING[@]}"; then
        echo "  $(t "Не все пакеты поставились; продолжаю — сборка сообщит, если не хватает нужного ей." \
                    "Not every package was installed; going on — the build reports anything it really needs.")" >&2
    fi
fi

# internet: themes and the LazyVim starter come from GitHub; without it they are skipped
ONLINE=
curl -fsS --max-time 8 -o /dev/null https://github.com 2>/dev/null && ONLINE=1

# ---- 1b. isolated LazyVim installation ---------------------------------------------------------
say "Среда программирования LazyVim" "LazyVim development environment"
if [ -z "$ONLINE" ]; then
    echo "  $(t "Нет доступа к GitHub: LazyVim пропущен." "No access to GitHub: LazyVim skipped.")"
elif ! bash ./scripts/install-lazyvim.sh; then
    # optional: the shell works without it
    echo "  $(t "LazyVim не установлен; остальное ставится дальше." "LazyVim was not set up; the rest goes on.")" >&2
fi

# ---- 2. build ----------------------------------------------------------------------------------
if [ -n "$BUILD" ]; then
    say "Сборка компонентов" "Building components"
    PREFIX="$SHARE" TABLET_SHELL_SKIP_FAILED_BUILDS="$SKIP_FAILED_BUILDS" \
        TABLET_SHELL_EXCLUDE_INPUT_LOCK="$([ -n "$PROTECT_INPUT_LOCK" ] && echo 1 || echo 0)" bash ./build.sh
fi
# Validate every artifact before deploying anything. A skipped target must have a working
# installed version. Otherwise we stop before any program or QML is replaced.
SKIPPED_COMPONENTS=()
component_target() {
    case "$1" in
      tabletd|tablet-tools) printf '%s/tabletd/%s' "$SHARE" "$1" ;;
      tabletshell|tablet-settings|tablet-keyboard|tablet-greeter) printf '%s/%s/%s' "$SHARE" "$1" "$1" ;;
      webapp-runner) printf '%s/webapps/runner/webapp-runner' "$SHARE" ;;
      translations) printf '%s/tablet-i18n/en.json' "$SHARE" ;;
      shaders) printf '%s/plasma/plasmoids/org.ipad.homescreen/contents/ui/shaders/weather.frag.qsb' "$SHARE" ;;
      sounds-shell) printf '%s/tabletshell/sounds' "$SHARE" ;;
      sounds-keyboard) printf '%s/tablet-keyboard/sounds' "$SHARE" ;;
    esac
}
component_build() {
    case "$1" in
      translations) printf 'build/en.json' ;;
      shaders) printf 'build/weather.frag.qsb' ;;
      sounds-shell) printf 'build/sounds/shell' ;;
      sounds-keyboard) printf 'build/sounds/keyboard' ;;
      *) printf 'build/%s' "$1" ;;
    esac
}
skipped() { [ -f "build/.skipped/$1" ]; }
# Intentional exclusions are not build failures and do not mark updates partial.
protected() {
    [ -n "$PROTECT_INPUT_LOCK" ] || return 1
    case "$1" in tablet-keyboard|tablet-greeter|sounds-keyboard) return 0 ;; esac
    return 1
}

for component in translations tabletd tablet-tools tabletshell tablet-settings tablet-keyboard tablet-greeter webapp-runner shaders sounds-shell sounds-keyboard; do
    protected "$component" && continue
    if skipped "$component"; then
        [ "$SKIP_FAILED_BUILDS" = 1 ] || die "Неожиданный пропуск: $component" "Unexpected skipped build: $component"
        [ -e "$(component_target "$component")" ] || die "Нет установленной версии: $component" "No installed fallback: $component"
        SKIPPED_COMPONENTS+=("$component")
    else
        artifact=$(component_build "$component")
        [ -e "$artifact" ] || die "Отсутствует результат сборки: $component" "Missing build artifact: $component"
        if [ -f "$artifact" ]; then
            [ -s "$artifact" ] || die "Пустой результат сборки: $component" "Empty build artifact: $component"
        fi
    fi
done
if ((${#SKIPPED_COMPONENTS[@]})); then
    printf '  Partial build / Частичная сборка — preserved: %s\n' "${SKIPPED_COMPONENTS[*]}" >&2
fi

# ---- 2b. copy of the KDE settings ---------------------------------------------------------------
# The installer changes the running session's settings: keep a copy of every file it touches
# first, with a script that puts them back (uninstall.sh removes the shell itself).
CONFIG_BACKUP=$HOME/.local/state/tablet-shell/config-backup-$(date +%Y%m%d-%H%M%S)
mkdir -p "$CONFIG_BACKUP"
# the last five copies are enough
ls -1d "$HOME"/.local/state/tablet-shell/config-backup-* 2>/dev/null | head -n -5 | xargs -r rm -rf --
for f in kwinrc kdeglobals kded6rc dolphinrc plasmarc plasmashellrc plasma-org.kde.plasma.desktop-appletsrc \
         kscreenlockerrc plasmamobilerc baloofilerc plasma-localerc kglobalshortcutsrc kcminputrc kxkbrc \
         powerdevilrc ksmserverrc kwinrulesrc; do
    [ -f "$HOME/.config/$f" ] && cp -a "$HOME/.config/$f" "$CONFIG_BACKUP/"
done
cat > "$CONFIG_BACKUP/restore.sh" <<'RESTORE'
#!/bin/bash
# Puts back the KDE settings saved before tablet-shell changed them, then restarts Plasma.
cd "$(dirname "$(readlink -f "$0")")"
systemctl --user stop plasma-plasmashell.service
for f in *rc; do cp -a "$f" "$HOME/.config/$f"; done
qdbus6 org.kde.KWin /KWin reconfigure 2>/dev/null || true
systemctl --user start plasma-plasmashell.service
echo "Restored from $PWD"
RESTORE
chmod +x "$CONFIG_BACKUP/restore.sh"
echo "  $(t "Копия настроек KDE: $CONFIG_BACKUP (вернуть: restore.sh там)" "Copy of the KDE settings: $CONFIG_BACKUP (put back: restore.sh there)")"

# ---- 3. files ----------------------------------------------------------------------------------
say "Файлы" "Files"
# SRC DST: DST becomes a copy of SRC (backups *.bak* / *.orig and local state files are kept)
sync_dir() {
    mkdir -p "$2"
    # Obsolete files are deleted by managed-files.py ONLY if recorded and unchanged.
    rsync -a --filter='P *.bak*' --filter='P *.orig' --filter='P previous-input-method.txt' "$1/" "$2/"
}
# programs with their QML
skipped tabletshell || sync_dir src/tabletshell "$SHARE/tabletshell"
skipped tablet-settings || sync_dir src/tablet-settings "$SHARE/tablet-settings"
if ! protected tablet-keyboard && ! skipped tablet-keyboard; then sync_dir src/tablet-keyboard "$SHARE/tablet-keyboard"; fi
if ! protected tablet-greeter && ! skipped tablet-greeter; then sync_dir src/tablet-greeter "$SHARE/tablet-greeter"; fi
mkdir -p "$SHARE/tabletd" "$SHARE/webapps/runner"
for component in tabletd tablet-tools tabletshell tablet-settings tablet-keyboard tablet-greeter webapp-runner; do
    if ! protected "$component" && ! skipped "$component"; then
        install -m755 "build/$component" "$(component_target "$component")"
    fi
done
skipped webapp-runner || install -m644 src/webapp-runner/webapp.qml "$SHARE/webapps/runner/"
mkdir -p "$SHARE/tabletshell/sounds"
if ! protected sounds-keyboard; then mkdir -p "$SHARE/tablet-keyboard/sounds"; fi
if ! skipped sounds-shell && ! skipped tabletshell; then cp build/sounds/shell/*.wav "$SHARE/tabletshell/sounds/"; fi
if ! protected sounds-keyboard && ! skipped sounds-keyboard && ! skipped tablet-keyboard; then cp build/sounds/keyboard/*.wav "$SHARE/tablet-keyboard/sounds/"; fi
skipped translations || install -Dm644 build/en.json "$SHARE/tablet-i18n/en.json"
# Plasma: home screen, dashboard, day/night wallpaper, iPad global themes, KWin scripts
for p in shell/plasmoids/*; do
    [ "$(basename "$p")" = org.ipad.homescreen ] && skipped shaders && continue
    sync_dir "$p" "$SHARE/plasma/plasmoids/$(basename "$p")"
done
skipped shaders || install -Dm644 build/weather.frag.qsb "$SHARE/plasma/plasmoids/org.ipad.homescreen/contents/ui/shaders/weather.frag.qsb"
skipped shaders || [ ! -s build/themed-icon.frag.qsb ] || install -Dm644 build/themed-icon.frag.qsb "$SHARE/plasma/plasmoids/org.ipad.homescreen/contents/ui/shaders/themed-icon.frag.qsb"
sync_dir shell/wallpapers/org.ipad.daynight "$SHARE/plasma/wallpapers/org.ipad.daynight"
# bundled wallpaper packages: Apple-like and Material-specific day/night packs
if [ -d shell/wallpaper-packs ]; then
    for p in shell/wallpaper-packs/*; do
        [ -d "$p" ] || continue
        sync_dir "$p" "$SHARE/wallpapers/$(basename "$p")"
    done
fi
for p in shell/desktoptheme/*; do sync_dir "$p" "$SHARE/plasma/desktoptheme/$(basename "$p")"; done
# the Pixel themes follow the colour scheme now (Material You): no colours of their own
rm -f "$SHARE"/plasma/desktoptheme/tablet-pixel-*/colors
# compact rounded task highlight instead of a block over the whole task cell (Pixel and WhiteSur)
python3 -I scripts/make-task-highlight.py "$SHARE"/plasma/desktoptheme/tablet-pixel-* >/dev/null
python3 -I scripts/make-task-highlight.py --apple "$SHARE"/plasma/desktoptheme/WhiteSurLiquid* >/dev/null
rm -f "$HOME"/.cache/plasma-svgelements-* "$HOME"/.cache/plasma_theme_*.kcache
sync_dir shell/color-schemes "$SHARE/color-schemes"
# Pixel uses its own symbols for panels and shell actions; unknown app icons
# inherit Colloid/Breeze. Apple's original MacTahoe theme is left unchanged.
if [ -d shell/icons ]; then
    for icon_pack in shell/icons/*; do
        [ -d "$icon_pack" ] || continue
        if [ "$(basename "$icon_pack")" = TabletPixel ]; then
            # keep locally-generated /apps/scalable drawings on updates
            mkdir -p "$SHARE/icons/TabletPixel"
            rsync -a --filter='P /apps/scalable/***' --filter='P /symbolic/***' "$icon_pack/" "$SHARE/icons/TabletPixel/"
        else
            sync_dir "$icon_pack" "$SHARE/icons/$(basename "$icon_pack")"
        fi
    done
    # after all three Pixel themes are in place (syncing a variant replaces its folder)
    python3 -I scripts/pixel-symbolic-icons.py "$SHARE/icons" src shell || true
fi
for p in shell/look-and-feel/*; do sync_dir "$p" "$SHARE/plasma/look-and-feel/$(basename "$p")"; done
for p in shell/kwin/scripts/*; do sync_dir "$p" "$SHARE/kwin/scripts/$(basename "$p")"; done
sync_dir shell/tablet-mode "$SHARE/tablet-mode"
# Upgrade the active bundled Pixel surfaces even when --update-only preserves other preferences.
# Do not call shell-style here: that would also change the user's current wallpaper.
if [ -n "$UPDATE_ONLY" ] && [ "$(kreadconfig6 --file tabletrc --group Appearance --key shellStyle 2>/dev/null)" = pixel ]; then
    pixel_variant=light
    case "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage 2>/dev/null)" in
        *dark*|*Dark*) pixel_variant=dark ;;
    esac
    kw --file kdeglobals --group Icons --key Theme "TabletPixel${pixel_variant^}"
    if command -v plasma-apply-desktoptheme >/dev/null; then
        plasma-apply-desktoptheme "tablet-pixel-$pixel_variant" || true
    fi
    if command -v plasma-apply-colorscheme >/dev/null; then
        if [ "$pixel_variant" = dark ]; then pixel_colors=TabletPixelDark; else pixel_colors=TabletPixelLight; fi
        plasma-apply-colorscheme "$pixel_colors" || true
    fi
fi
# commands
mkdir -p "$BIN"
for f in bin/*; do
    # lockscreen-sync is bundled but not changed by the normal updater.
    if [ -n "$PROTECT_INPUT_LOCK" ] && [ "$(basename "$f")" = lockscreen-sync ]; then continue; fi
    install -m755 "$f" "$BIN/"
done
# Bundled icons always work offline; fetching complete Material app logos is optional.
if [ -z "$UPDATE_ONLY" ] || [ "${TABLET_SHELL_DOWNLOAD_ICONS:-0}" = 1 ]; then
    bash scripts/install-material-icons.sh || echo '  Material icon download unavailable; bundled fallback retained.'
fi
skipped tabletd || ln -sf "$SHARE/tabletd/tabletd" "$BIN/tabletd"
skipped tabletshell || ln -sf "$SHARE/tabletshell/tabletshell" "$BIN/tabletshell"
skipped tablet-settings || ln -sf "$SHARE/tablet-settings/tablet-settings" "$BIN/tablet-settings"
if ! protected tablet-keyboard && ! skipped tablet-keyboard; then
    ln -sf "$SHARE/tablet-keyboard/tablet-keyboard" "$BIN/tablet-keyboard"
fi
skipped webapp-runner || ln -sf "$SHARE/webapps/runner/webapp-runner" "$BIN/webapp-runner"
if ! skipped tablet-tools; then
    for l in tablet-tools wallpaper webapp-create screentime-apps; do ln -sf "$SHARE/tabletd/tablet-tools" "$BIN/$l"; done
fi
# app entries, data
mkdir -p "$SHARE/applications"
for f in applications/*.desktop; do
    if [ -n "$PROTECT_INPUT_LOCK" ] && [ "$(basename "$f")" = tablet-keyboard.desktop ]; then continue; fi
    sed "s|@HOME@|$HOME|g" "$f" > "$SHARE/applications/$(basename "$f")"
done
# Fill missing icons for BOTH families after new .desktop entries have been installed.
"$BIN/app-icons-refresh" || true
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
# The system scripts and updater are accessible from Settings even when the
# original project directory came from a ZIP and no Git checkout exists.
if [ -n "$PROTECT_INPUT_LOCK" ]; then
    # System greeter launcher/scripts remain at their installed versions as well.
    mkdir -p "$SHARE/tablet-shell/system"
    rsync -a --exclude='/greeter.sh' --exclude='/greeter-launch.sh' --exclude='/refresh-greetd.py' \
        system/ "$SHARE/tablet-shell/system/"
else
    sync_dir system "$SHARE/tablet-shell/system"
fi
install -m755 update.sh "$SHARE/tablet-shell/update.sh"

if [ -z "$UPDATE_ONLY" ]; then
# ---- 4. themes ---------------------------------------------------------------------------------
# Downloads (themes from GitHub at pinned commits: git checks the content against the commit) are
# optional: offline, or when GitHub fails, the shell installs without them.
if [ -n "$THEMES" ]; then
    say "Темы WhiteSur (загрузка)" "WhiteSur themes (download)"
    if [ -z "$ONLINE" ]; then
        echo "  $(t "Нет доступа к GitHub: темы пропущены (позже: ./install.sh --update-only после scripts/themes.sh)." "No access to GitHub: themes skipped (later: scripts/themes.sh, then ./install.sh --update-only).")"
    elif ! bash scripts/themes.sh; then
        echo "  $(t "Темы не скачались; оболочка ставится со стандартными." "The themes did not download; the shell is installed with the standard ones.")" >&2
    fi
fi

# ---- 5. hardware -------------------------------------------------------------------------------
say "Устройство" "Device"
HW=$("$BIN/tablet-tools" hardware)
# the device kind decides the device-specific system parts (system/devices.sh)
case "$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)|$(cat /sys/class/dmi/id/product_name /sys/class/dmi/id/product_version 2>/dev/null | tr '\n' ' ')" in
    LENOVO*"ThinkPad 10"*) KIND="ThinkPad 10" ;;
    Microsoft*"|Surface"*) KIND="Microsoft Surface: $(t "касания и перо через iptsd (linux-surface)" "touch and pen through iptsd (linux-surface)")" ;;
    *) KIND=$(t "другое устройство: общие настройки" "another device: general settings") ;;
esac
echo "  $KIND"
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
STYLE=$(kreadconfig6 --file tabletrc --group Appearance --key shellStyle 2>/dev/null || true)
if [ "$STYLE" = pixel ]; then STYLEPKG=org.tabletshell.pixel; else STYLEPKG=org.ipad; STYLE=apple; fi
kw --file kdeglobals --group KDE --key DefaultLightLookAndFeel "$STYLEPKG.light"
kw --file kdeglobals --group KDE --key DefaultDarkLookAndFeel "$STYLEPKG.dark"
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
# the lock screen shows the same wallpaper package; default depends on the whole-shell style
if [ "$STYLE" = pixel ]; then
    WP=$SHARE/wallpapers/Material-Orbit
    [ -d "$WP" ] || WP=$(ls -d "$SHARE"/wallpapers/Material-* 2>/dev/null | head -1)
else
    WP=$SHARE/wallpapers/Monterey-iPad
    [ -d "$WP" ] || WP=$(ls -d "$SHARE"/wallpapers/*-iPad 2>/dev/null | head -1)
fi
if [ -n "$WP" ] && [ -z "$(kreadconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.ipad.daynight --group General --key Image)" ]; then
    kw --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.ipad.daynight
    kw --file kscreenlockerrc --group Greeter --group Wallpaper --group org.ipad.daynight --group General --key Image "file://$WP/"
fi

fi  # Existing settings, weather, themes and hardware preferences remain unchanged on update.

# ---- 7. services -------------------------------------------------------------------------------
say "Службы" "Services"
mkdir -p "$HOME/.config/systemd/user"
for unit in systemd/*; do
    case "$(basename "$unit")" in
      lockscreen-sync.*|greeter-wallpaper.*)
          if [ -n "$PROTECT_INPUT_LOCK" ]; then continue; fi ;;
    esac
    cp "$unit" "$HOME/.config/systemd/user/"
done
systemctl --user daemon-reload
# Do not silently re-enable user-disabled services during an update.
# Refresh the installed lock screen on updates too: QML and Pixel style are copied
# without modifying the user's lock-screen preferences or resetting Plasma widgets.
if [ -z "$PROTECT_INPUT_LOCK" ]; then
    if ! bash "$BIN/lockscreen-sync"; then
        echo "  $(t 'Не удалось обновить блокировку; проверьте активную тему Plasma.' 'Failed to update the lock screen; check the active Plasma shell.')" >&2
        exit 1
    fi
fi
if [ -z "$UPDATE_ONLY" ]; then
    "$BIN/taskswitcher-sync" || true
    systemctl --user enable tabletd.service tabletshell.service lockscreen-sync.service lockscreen-sync.path app-icons.path \
        taskswitcher-sync.service taskswitcher-sync.path greeter-wallpaper.path greeter-wallpaper.timer >/dev/null 2>&1
fi

# ---- 8. apply ----------------------------------------------------------------------------------
say "Применение" "Applying"
if [ -z "$UPDATE_ONLY" ]; then
FIRST=
[ "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)" = org.ipad.light ] || \
    [ "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)" = org.ipad.dark ] || \
    [ "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)" = org.tabletshell.pixel.light ] || \
    [ "$(kreadconfig6 --file kdeglobals --group KDE --key LookAndFeelPackage)" = org.tabletshell.pixel.dark ] || FIRST=1
if [ -n "$FIRST" ]; then
    plasma-apply-lookandfeel -a "$STYLEPKG.light" >/dev/null 2>&1 || true
    kw --file kdeglobals --group KDE --key AutomaticLookAndFeel true
fi
containments
# weather city on the home screen and the dashboard, coordinates for the day/night wallpaper
# Avoid a fixed delay on subsequent installs; poll for Plasma's D-Bus endpoint.
for ((i=0; i<8; i++)); do
    qdbus6 org.kde.plasmashell /PlasmaShell org.freedesktop.DBus.Introspectable.Introspect >/dev/null 2>&1 && break
    sleep 1
done
# Quote free-form city and wallpaper strings as JavaScript string literals.
CITY_JS=$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1],ensure_ascii=True))' "$CITY")
WP_JS=$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1],ensure_ascii=True))' "file://$WP/")
qdbus6 org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "
desktops().forEach(function (d) {
    d.currentConfigGroup = ['General'];
    d.writeConfig('shellStyle', '$STYLE');
    if (!d.readConfig('weatherCity', '')) d.writeConfig('weatherCity', $CITY_JS);
    if ('$LAT' !== '') {
        d.wallpaperPlugin = 'org.ipad.daynight';
        d.currentConfigGroup = ['Wallpaper', 'org.ipad.daynight', 'General'];
        d.writeConfig('Latitude', $LAT + 0); d.writeConfig('Longitude', $LON + 0);
        if (!d.readConfig('Image', '')) d.writeConfig('Image', $WP_JS);
    }
    d.reloadConfig();
});" >/dev/null 2>&1 || true
fi
# Enable alone defers path and timer units until the next login.
if [ -z "$UPDATE_ONLY" ]; then
    systemctl --user start lockscreen-sync.path app-icons.path taskswitcher-sync.path
    systemctl --user start greeter-wallpaper.path greeter-wallpaper.timer
    systemctl --user restart tabletd.service tabletshell.service
else
    # Restart only services whose executable was successfully rebuilt.
    # A failed daemon build must not disturb its still-running previous version.
    refresh_services=()
    skipped tabletd || refresh_services+=(tabletd.service)
    skipped tabletshell || refresh_services+=(tabletshell.service)
    if ((${#refresh_services[@]})); then
        systemctl --user try-restart "${refresh_services[@]}"
    fi
fi
# Trigger an immediate panel repair after replacing the daemon.
# Startup retries remain responsible for Plasma sessions still loading.
qdbus6 org.ipad.TabletD / org.ipad.TabletD.Reapply >/dev/null 2>&1 || true
# KWin owns the input method. Killing its client can leave no keyboard until next
# login; keep the running instance and load the updated binary on next login.
if ! protected tablet-keyboard && ! skipped tablet-keyboard; then
    # Do not silently change a user-selected third-party input method.
    current_im=$(kreadconfig6 --file kwinrc --group Wayland --key InputMethod 2>/dev/null || true)
    case "$current_im" in
        *tablet-keyboard.desktop)
            kw --file kwinrc --group Wayland --key InputMethod "$SHARE/applications/tablet-keyboard.desktop" ;;
    esac
    echo "  $(t 'Клавиатура обновлена на диске; активируется при следующем входе в сеанс.' 'Keyboard updated on disk; it will activate after the next login.')"
fi
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true

# Remove only stale, previously recorded, unchanged tablet-shell files. Unknown and
# locally modified files are preserved. The first run establishes the ownership list;
# previously unknown legacy files are not guessed or deleted.
MANAGED_ARGS=()
if [ -n "$PROTECT_INPUT_LOCK" ]; then
    MANAGED_ARGS+=(--reuse-component tablet-keyboard --reuse-component tablet-greeter
                   --reuse-component input-lock-assets)
fi
for component in "${SKIPPED_COMPONENTS[@]}"; do MANAGED_ARGS+=(--reuse-component "$component"); done
python3 -I scripts/managed-files.py --source "$REPO" --home "$HOME" "${MANAGED_ARGS[@]}" || \
    echo "  $(t "Очистка пропущена (ошибка безопасной проверки)." "Safe obsolete-file cleanup was skipped.")" >&2

# A partial update is not advertised as a complete GitHub revision.
if ((${#SKIPPED_COMPONENTS[@]})); then
    mkdir -p "$SHARE/tablet-shell"
    printf '%s\n' "${SKIPPED_COMPONENTS[@]}" > "$SHARE/tablet-shell/last-skipped-components"
else
    rm -f "$SHARE/tablet-shell/last-skipped-components"
fi

# The version marker is written only after a successful installation, never
# halfway through the update. A local ZIP build stays "local", rather than
# pretending to be an old remote commit left behind from a previous install.
VERSION_SHA=${TABLET_SHELL_SOURCE_COMMIT:-}
if [[ ! "$VERSION_SHA" =~ ^[a-f0-9]{40}$ ]] && [ -d "$REPO/.git" ]; then
    VERSION_SHA=$(git -C "$REPO" rev-parse HEAD 2>/dev/null || true)
fi
if ((${#SKIPPED_COMPONENTS[@]})); then
    printf 'partial\n' > "$SHARE/tablet-shell/version"
elif [[ "$VERSION_SHA" =~ ^[a-f0-9]{40}$ ]]; then
    printf '%s\n' "$VERSION_SHA" > "$SHARE/tablet-shell/version"
else
    printf 'local\n' > "$SHARE/tablet-shell/version"
fi

# the release number (VERSION in the repository, e.g. 0.5.0), shown by Settings → Updates
if [ -f "$REPO/VERSION" ]; then
    tr -cd '0-9A-Za-z.+~-' < "$REPO/VERSION" | head -c 32 > "$SHARE/tablet-shell/release"
fi

# ---- 8b. system parts (sudo) ---------------------------------------------------------------------
# At the end: base.sh may switch the network over to NetworkManager, nothing may need it after that.
# system/apply.sh runs every part on its own and reports each one (logs in ~/.local/state/tablet-shell).
GREETER_PENDING="$HOME/.local/state/tablet-shell/greeter-refresh-needed"
# Material You: the Pixel colour schemes from the wallpaper (the bundled ones above are the
# baseline purple); applied at once when the Pixel look is on
"$BIN/tablet-tools" material-you --apply >/dev/null 2>&1 || true

GREETER_INSTALLED=
[ -r /etc/greetd/config.toml ] && grep -Eq 'tablet-greeter|tablet-shell-greeter' /etc/greetd/config.toml && GREETER_INSTALLED=1
if [ -n "$SUDO_OK" ]; then
    say "Системные части" "System parts"
    APPLY=(--full)
    [ -z "$UPDATE_ONLY" ] || APPLY=(--update)
    { [ -n "$GREETER" ] || [ -n "$GREETER_INSTALL" ]; } && APPLY+=(--greeter)
    [ -z "$ANDROID" ] || APPLY+=(--android)
    [ -n "$GREETER_UPDATE" ] || APPLY+=(--no-greeter-refresh)
    APPLY_OUT=$(sudo -n bash "$REPO/system/apply.sh" "${APPLY[@]}" 2>&1) || true
    printf '%s\n' "$APPLY_OUT" | sed -E 's/^PART [^ ]+ ok (.*)/  ok       \1/; s/^PART [^ ]+ skipped (.*)/  '"$(t пропущено skipped)"'  \1/'
    grep -q '^PART greeter.sh skipped' <<<"$APPLY_OUT" || rm -f "$GREETER_PENDING"
elif [ -n "$GREETER_INSTALLED" ] && [ -n "$GREETER_UPDATE" ]; then
    mkdir -p "$(dirname "$GREETER_PENDING")"
    printf 'Login screen refresh requires administrator permission.\n' > "$GREETER_PENDING"
    echo "  $(t 'Экран входа требует отдельного подтверждения sudo:' 'The login screen still needs sudo approval:')" >&2
    echo "  sudo '$SHARE/tablet-shell/system/greeter.sh' --refresh" >&2
fi

# ---- 9. what is left -----------------------------------------------------------------------------
say "Готово" "Done"
if [ -n "$UPDATE_ONLY" ]; then
    echo "  $(t 'Клавиатура, блокировка и экран входа сохранены без изменений.' 'Keyboard, lock screen and login screen were left unchanged.')"
    if ((${#SKIPPED_COMPONENTS[@]})); then
        echo "  PARTIAL UPDATE / ЧАСТИЧНО: ${SKIPPED_COMPONENTS[*]}" >&2
    else
        echo "  $(t "Обновление выполнено. Для полного применения изменений интерфейса выйдите и войдите снова." "Update applied. Log out and back in to reload the full interface.")"
    fi
    exit 0
fi
t "Оболочка установлена. Полностью она включится после выхода из сеанса и входа снова." \
  "The shell is installed. Log out and back in for everything to take effect."; echo
if [ -n "$SUDO_OK" ]; then
    [ -n "$ANDROID" ] || echo "  $(t "Android по желанию: ./install.sh --android или" "Android if wanted: ./install.sh --android or") sudo $SHARE/tablet-shell/system/android/install.sh"
    exit 0
fi
t "Системные части (через sudo):" "System parts (with sudo):"; echo
cat <<EOF
  sudo $SHARE/tablet-shell/system/apply.sh --full --greeter  $(t "всё сразу (то же, что ниже, кроме Android)" "all at once (the list below except Android)")
  sudo $SHARE/tablet-shell/system/devices.sh            $(t "доступ к кнопкам, перу, экрану, клавиатуре; Rnote" "access to buttons, pen, touch screen, keyboard; Rnote")
  sudo $SHARE/tablet-shell/system/settings-wrappers.sh  $(t "«Настройки» вместо Параметров системы" "Tablet Settings instead of System Settings")
  sudo $SHARE/tablet-shell/system/greeter.sh            $(t "свой экран входа" "own login screen")
  sudo $SHARE/tablet-shell/system/base.sh               $(t "NetworkManager, Bluetooth, zram, приложения" "NetworkManager, Bluetooth, zram, apps")
  sudo $SHARE/tablet-shell/system/language.sh ru|en     $(t "язык системы" "system language")
  sudo $SHARE/tablet-shell/system/recovery/install.sh   $(t "снимки системы (Arch: btrfs + systemd-boot)" "system snapshots (Arch: btrfs + systemd-boot)")
  sudo $SHARE/tablet-shell/system/boot-splash/install.sh $(t "заставка загрузки" "boot splash")
  sudo $SHARE/tablet-shell/system/android/install.sh    Android (Waydroid)
EOF
