#!/bin/bash
# Make Plasma's own "open settings" calls (systemsettings / kcmshell6 by name, e.g. "Configure
# Display Settings…" in the tray) open the tablet-settings app instead of KDE System Settings.
# /usr/local/bin comes before /usr/bin in PATH.
# Run: sudo ./system/settings-wrappers.sh     Undo: sudo ./system/settings-wrappers.sh --undo
source "$(dirname "$(readlink -f "$0")")/common.sh"
APP=$H/.local/bin/tablet-settings
# where this distribution keeps the Qt 6 plugins (/usr/lib/qt6, /usr/lib64/qt6, /usr/lib/<arch>/qt6)
KCMS=$(qtpaths6 --query QT_INSTALL_PLUGINS 2>/dev/null || qmake6 -query QT_INSTALL_PLUGINS 2>/dev/null)
for d in "$KCMS" /usr/lib/qt6/plugins /usr/lib64/qt6/plugins /usr/lib/*-linux-gnu*/qt6/plugins; do
    [ -d "$d/plasma/kcms/systemsettings" ] && { KCMS=$d/plasma/kcms/systemsettings; break; }
done

if [ "${1:-}" = --undo ]; then
    rm -f /usr/local/bin/systemsettings /usr/local/bin/kcmshell6
    exit 0
fi

cat > /usr/local/bin/systemsettings <<WRAP
#!/bin/sh
# System Settings is replaced by tablet-settings (module ids are passed through)
[ -x "$APP" ] || exec /usr/bin/systemsettings "\$@"
for a in "\$@"; do case "\$a" in -*) ;; *) exec "$APP" "\$a" ;; esac; done
exec "$APP"
WRAP

cat > /usr/local/bin/kcmshell6 <<WRAP
#!/bin/sh
# Settings modules that tablet-settings embeds open there; everything else stays with kcmshell6
for a in "\$@"; do
    case "\$a" in -*) continue ;; esac
    if [ -x "$APP" ] && [ -f "$KCMS/\$a.so" ]; then
        exec "$APP" "\$a"
    fi
    break
done
exec /usr/bin/kcmshell6 "\$@"
WRAP
chmod 755 /usr/local/bin/systemsettings /usr/local/bin/kcmshell6
t "Готово: systemsettings и kcmshell6 открывают Настройки планшета." "Done: systemsettings and kcmshell6 now open Tablet Settings."; echo
