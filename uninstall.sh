#!/bin/bash
# Removes the tablet shell for the current user and returns to the standard Plasma desktop.
# Kept: your texts (~/Сценарии), screen time history, web apps, the WhiteSur themes and the
# shell's settings files (~/.config/tablet*rc). System parts are undone with their own --undo.
set -e
SHARE=$HOME/.local/share
BIN=$HOME/.local/bin
case "$(kreadconfig6 --file plasma-localerc --group Translations --key LANGUAGE 2>/dev/null)${LANG:-}" in ru*) RU=1 ;; *) RU= ;; esac
t() { if [ -n "$RU" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }

systemctl --user disable --now tabletd.service tabletshell.service lockscreen-sync.service lockscreen-sync.path \
    taskswitcher-sync.service taskswitcher-sync.path greeter-wallpaper.path greeter-wallpaper.timer 2>/dev/null || true
for u in tabletd.service tabletshell.service lockscreen-sync.service lockscreen-sync.path taskswitcher-sync.service \
         taskswitcher-sync.path greeter-wallpaper.service greeter-wallpaper.path greeter-wallpaper.timer; do
    rm -f "$HOME/.config/systemd/user/$u"
done
systemctl --user daemon-reload

# the standard look, keyboard and desktop
kwriteconfig6 --file kdeglobals --group KDE --key AutomaticLookAndFeel false
plasma-apply-lookandfeel -a org.kde.breeze.desktop >/dev/null 2>&1 || true
prev=$(cat "$SHARE/tablet-keyboard/previous-input-method.txt" 2>/dev/null || true)
kwriteconfig6 --file kwinrc --group Wayland --key InputMethod "${prev:-/usr/share/applications/org.kde.plasma.keyboard.desktop}"
for s in tablet-gestures split-view slide-over picture-in-picture dock-mode; do
    kwriteconfig6 --file kwinrc --group Plugins --key "${s}Enabled" --delete
done
kwriteconfig6 --file kwinrc --group ModifierOnlyShortcuts --key Meta --delete
kwriteconfig6 --file kwinrc --group Input --key TabletMode auto
rc=$HOME/.config/plasma-org.kde.plasma.desktop-appletsrc
systemctl --user stop plasma-plasmashell.service
sed -i 's/^plugin=org.ipad.homescreen$/plugin=org.kde.plasma.folder/; s/^plugin=org.ipad.dashboard$/plugin=org.kde.plasma.folder/;
        s/^wallpaperplugin=org.ipad.daynight$/wallpaperplugin=org.kde.image/' "$rc"
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin --delete

rm -rf "$SHARE/tabletshell" "$SHARE/tablet-settings" "$SHARE/tablet-keyboard" "$SHARE/tablet-greeter" "$SHARE/tabletd" \
    "$SHARE/tablet-i18n" "$SHARE/tablet-mode" "$SHARE/tablet-shell" "$SHARE/webapps/runner" \
    "$SHARE/plasma/plasmoids/org.ipad.homescreen" "$SHARE/plasma/plasmoids/org.ipad.dashboard" \
    "$SHARE/plasma/wallpapers/org.ipad.daynight" "$SHARE/plasma/look-and-feel/org.ipad.light" \
    "$SHARE/plasma/look-and-feel/org.ipad.dark" "$SHARE/plasma/shells/org.kde.plasma.desktop" \
    "$SHARE/kwin/effects/mobiletaskswitcher"
for s in tablet-gestures split-view slide-over picture-in-picture dock-mode; do rm -rf "$SHARE/kwin/scripts/$s"; done
for f in appearance lockscreen-sync quick-note reading-mode taskswitcher-sync typewriter youtube-setup tabletd tabletshell \
         tablet-settings tablet-keyboard tablet-tools wallpaper webapp-create webapp-runner screentime-apps; do
    rm -f "$BIN/$f"
done
rm -f "$SHARE/applications/tablet-keyboard.desktop" "$SHARE/applications/typewriter.desktop" \
    "$SHARE/applications/appearance-toggle.desktop" "$SHARE/applications/systemsettings.desktop"
systemctl --user start plasma-plasmashell.service
qdbus6 org.kde.KWin /KWin reconfigure >/dev/null 2>&1 || true

t "Оболочка удалена. Системные части отменяются отдельно:" "The shell is removed. System parts are undone separately:"; echo
echo "  sudo <repo>/system/greeter.sh --undo; sudo <repo>/system/settings-wrappers.sh --undo; sudo <repo>/system/devices.sh --undo"
