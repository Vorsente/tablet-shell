#!/bin/bash
# Own login screen: greetd (login daemon: PAM, logind session, VT) + cage (kiosk compositor) +
# tablet-greeter (looks like the shell's lock screen). Replaces plasmalogin / SDDM.
# Re-run after updating tablet-greeter (install.sh says when).
# Run: sudo ./system/greeter.sh              Undo: sudo ./system/greeter.sh --undo
source "$(dirname "$(readlink -f "$0")")/common.sh"
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
if grep -q '^COMPRESSION="lz4"' /etc/mkinitcpio.conf; then
    say "initramfs: lz4 → zstd" "initramfs: lz4 → zstd"
    sed -i 's/^COMPRESSION=.*/COMPRESSION="zstd"/' /etc/mkinitcpio.conf
    mkinitcpio -P >/dev/null
fi

say "Пакеты" "Packages"
pacman -S --needed --noconfirm greetd cage

say "Экран входа" "Login screen"
install -Dm755 "$SRC/tablet-greeter" /usr/local/bin/tablet-greeter
install -Dm644 -t /usr/local/share/tablet-greeter "$SRC/Main.qml" "$SRC/LockSurface.qml" "$SRC/Keyboard.qml" "$SRC/KeyFace.qml" \
    "$SRC/Tr.js" "$H/.local/share/tablet-i18n/en.json"
install -d -o greeter -g greeter /var/cache/tablet-greeter
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

cat > /etc/greetd/tablet-greeter.conf <<CONF
[General]
user=$U
session=/usr/share/wayland-sessions/plasma.desktop
wallpaper=/var/lib/tablet-greeter/wallpaper.jpg
CONF

cp -n /etc/greetd/config.toml /etc/greetd/config.toml.orig 2>/dev/null || true
cat > /etc/greetd/config.toml <<CONF
[terminal]
vt = 1

[default_session]
# -s: VT switching allowed, -m last: the newest output (the external monitor when docked)
command = "env QML_DISK_CACHE_PATH=/var/cache/tablet-greeter LANG=${LANG:-en_US.UTF-8} cage -s -m last -- /usr/local/bin/tablet-greeter"
user = "greeter"
CONF

# KWallet opens with the login password
if ! grep -q pam_kwallet5 /etc/pam.d/greetd; then
    printf -- '-auth       optional    pam_kwallet5.so\n-session    optional    pam_kwallet5.so auto_start\n' >> /etc/pam.d/greetd
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
