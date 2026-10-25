#!/bin/bash
# Own login screen: greetd (login daemon: PAM, logind session, VT) + cage (kiosk compositor) +
# tablet-greeter (looks like the shell's lock screen). Replaces plasmalogin / SDDM.
# Re-run after updating tablet-greeter (install.sh says when).
# Run: sudo ./system/greeter.sh              Undo: sudo ./system/greeter.sh --undo
source "$(dirname "$(readlink -f "$0")")/common.sh"
REFRESH=
if [ "${1:-}" = --refresh ]; then
    REFRESH=1
    if [ ! -f /etc/greetd/config.toml ] || ! grep -Eq "tablet-greeter|tablet-shell-greeter" /etc/greetd/config.toml; then
        echo "greetd is not configured for tablet-shell; not changing the login manager."
        exit 0
    fi
fi
SRC=$H/.local/share/tablet-greeter
OLD_DM=$(systemctl list-unit-files --state=enabled 'sddm.service' 'plasmalogin.service' 'gdm.service' 'lightdm.service' --no-legend 2>/dev/null | awk '{print $1}' | head -1)

if [ "${1:-}" = --undo ]; then
    prev=$(cat /var/lib/tablet-greeter/previous-dm 2>/dev/null || echo plasmalogin.service)
    systemctl disable greetd.service
    systemctl enable "$prev"
    t "Вернул $prev. Перезагрузитесь." "Restored $prev. Reboot."; echo
    exit 0
fi
[ -x "$SRC/tablet-greeter" ] || { t "Сначала запустите ./install.sh" "Run ./install.sh first"; echo; exit 1; }

# a kernel that cannot unpack an lz4 initramfs boots without it (no splash, no early graphics)
if [ -z "$REFRESH" ] && grep -q '^COMPRESSION="lz4"' /etc/mkinitcpio.conf; then
    say "initramfs: lz4 → zstd" "initramfs: lz4 → zstd"
    sed -i 's/^COMPRESSION=.*/COMPRESSION="zstd"/' /etc/mkinitcpio.conf
    mkinitcpio -P >/dev/null
fi

if [ -z "$REFRESH" ]; then
    say "Пакеты" "Packages"
    pacman -S --needed --noconfirm greetd cage
else
    command -v cage >/dev/null || { echo "Missing cage; cannot update greeter" >&2; exit 1; }
fi

say "Экран входа" "Login screen"
install -Dm755 "$SRC/tablet-greeter" /usr/local/bin/tablet-greeter
install -Dm755 "$SYSTEM_DIR/greeter-launch.sh" /usr/local/libexec/tablet-shell-greeter
install -Dm755 "$SYSTEM_DIR/session-launch.sh" /usr/local/libexec/tablet-shell-session
# the Plasma session behind the quiet wrapper (the greeter starts the Exec= line of this file)
install -d /usr/local/share/tablet-greeter
cat > /usr/local/share/tablet-greeter/plasma.desktop <<SESSION
[Desktop Entry]
Type=Application
Name=Plasma (Wayland)
Exec=/usr/local/libexec/tablet-shell-session $(sed -n 's/^Exec=//p' /usr/share/wayland-sessions/plasma.desktop | head -1)
SESSION
install -Dm644 -t /usr/local/share/tablet-greeter "$SRC/Main.qml" "$SRC/LockSurface.qml" "$SRC/Keyboard.qml" "$SRC/KeyFace.qml" \
    "$SRC/Tr.js" "$H/.local/share/tablet-i18n/en.json"
install -d -o greeter -g greeter /var/cache/tablet-greeter
# Remove the file created by old versions; no new session logs are written.
rm -f /var/cache/tablet-greeter/session.log
# wallpaper and look: files owned by the user, kept up to date by the shell (wallpaper sync,
# lockscreen-sync) without sudo
install -d -m755 /var/lib/tablet-greeter
for f in wallpaper.jpg lock.conf; do
    [ -f /var/lib/tablet-greeter/$f ] || touch /var/lib/tablet-greeter/$f
    chown "$U:" /var/lib/tablet-greeter/$f
    chmod 644 /var/lib/tablet-greeter/$f
done
[ -n "$OLD_DM" ] && [ "$OLD_DM" != greetd.service ] && echo "$OLD_DM" > /var/lib/tablet-greeter/previous-dm
as_user "$H/.local/bin/wallpaper" sync >/dev/null 2>&1 || true
[ -f "$H/.config/tablet-lockrc" ] && cat "$H/.config/tablet-lockrc" > /var/lib/tablet-greeter/lock.conf
# The material/apple choice is in per-user tabletrc; login greeter reads its own copy.
STYLE=$(as_user kreadconfig6 --file tabletrc --group Appearance --key shellStyle 2>/dev/null || true)
[ "$STYLE" = pixel ] || STYLE=apple
kwriteconfig6 --file /var/lib/tablet-greeter/lock.conf --group Login --key shellStyle "$STYLE"
chown "$U:" /var/lib/tablet-greeter/lock.conf

cat > /etc/greetd/tablet-greeter.conf <<CONF
[General]
user=$U
session=/usr/local/share/tablet-greeter/plasma.desktop
wallpaper=/var/lib/tablet-greeter/wallpaper.jpg
CONF

cp -n /etc/greetd/config.toml /etc/greetd/config.toml.orig 2>/dev/null || true
# On refresh preserve user changes to vt, additional tables and other greeter settings.
if [ -n "$REFRESH" ]; then
    cp -n /etc/greetd/config.toml /etc/greetd/config.toml.before-tablet-shell-refresh 2>/dev/null || true
    python3 -I "$SYSTEM_DIR/refresh-greetd.py" /etc/greetd/config.toml
else
    cat > /etc/greetd/config.toml <<'CONF'
[terminal]
vt = 1

[default_session]
command = "/usr/local/libexec/tablet-shell-greeter"
user = "greeter"
CONF
fi

# KWallet opens with the login password
if ! grep -q pam_kwallet5 /etc/pam.d/greetd; then
    printf -- '-auth       optional    pam_kwallet5.so\n-session    optional    pam_kwallet5.so auto_start\n' >> /etc/pam.d/greetd
fi

if [ -n "$REFRESH" ]; then
    say "Экран входа обновлён: вывод cage/libseat/seatd и сеанса на экран отключён" \
        "Login screen updated: cage/libseat/seatd and session output hidden"
    exit 0
fi

say "Вместо ${OLD_DM:-старого экрана входа}" "Replacing ${OLD_DM:-the old login screen}"
if [ -f /etc/plasmalogin.conf ]; then
    awk '/^\[Autologin\]/{skip=1; next} /^\[/{skip=0} !skip' /etc/plasmalogin.conf > /etc/plasmalogin.conf.new
    mv /etc/plasmalogin.conf.new /etc/plasmalogin.conf
fi
[ -n "$OLD_DM" ] && [ "$OLD_DM" != greetd.service ] && systemctl disable "$OLD_DM"
systemctl enable greetd.service
echo
t "Готово. Перезагрузитесь: появится новый экран входа." "Done. Reboot to see the new login screen."; echo
t "Если что-то не так: Ctrl+Alt+F2, войти в консоль и  sudo $0 --undo" "If anything goes wrong: Ctrl+Alt+F2, log in and run  sudo $0 --undo"; echo
