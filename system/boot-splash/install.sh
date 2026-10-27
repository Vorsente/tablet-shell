#!/bin/bash
# Boot splash: a pulsing Linux penguin on black (no distribution logo, no device name), quiet boot,
# no boot menu (hold Space while powering on to get it). Needs systemd-boot with a unified kernel
# image (UKI) from mkinitcpio.
# Run: sudo ./system/boot-splash/install.sh     Undo: restore the *.before-plymouth files, mkinitcpio -P
#      --theme-only: only replace the picture of an already set up splash (updates)
source "$(dirname "$(readlink -f "$0")")/../common.sh"
SRC="$(dirname "$(readlink -f "$0")")"
uki_boot || { t "Нужен systemd-boot с UKI (mkinitcpio default_uki): не меняю загрузку." \
                "Needs systemd-boot with a UKI (mkinitcpio default_uki): boot left unchanged."; echo; exit 1; }

pkg_install plymouth librsvg
T=/usr/share/plymouth/themes/tablet-linux
install -d "$T"
install -m644 "$SRC"/theme/tablet-linux.* "$T/"
# the penguin a little larger on big, sharp screens (the panel's height / 4, 200-420 px)
H=$(head -qn1 /sys/class/drm/card*-eDP-*/modes 2>/dev/null | head -1 | cut -dx -f2)
SIZE=$(( ${H:-1200} / 4 )); [ "$SIZE" -lt 200 ] && SIZE=200; [ "$SIZE" -gt 420 ] && SIZE=420
rsvg-convert -w "$SIZE" -h "$SIZE" "$SRC/theme/logo.svg" -o "$T/logo.png" 2>/dev/null || install -m644 "$SRC/theme/logo.png" "$T/"
rm -rf /usr/share/plymouth/themes/thinkpad-arch /usr/share/plymouth/themes/tablet-arch   # older names of this theme

# DeviceScale=1: high-dpi tablet screens would otherwise double the images
cat > /etc/plymouth/plymouthd.conf <<'CONF'
[Daemon]
Theme=tablet-linux
ShowDelay=0
DeviceScale=1
CONF
if [ "${1:-}" = --theme-only ]; then
    mkinitcpio -P >/dev/null
    t "Заставка загрузки обновлена." "Boot splash updated."; echo
    exit 0
fi

# initramfs: plymouth hook right after udev (the kms hook loads the GPU driver early)
cp -n /etc/mkinitcpio.conf /etc/mkinitcpio.conf.before-plymouth
grep -q '\bplymouth\b' /etc/mkinitcpio.conf || sed -i 's/^HOOKS=(base udev /HOOKS=(base udev plymouth /' /etc/mkinitcpio.conf

# kernel command line (the UKI reads /etc/kernel/cmdline): quiet boot with splash
cp -n /etc/kernel/cmdline /etc/kernel/cmdline.before-plymouth
for opt in quiet splash loglevel=3 rd.udev.log_level=3 udev.log_level=3 systemd.show_status=false rd.systemd.show_status=false vt.global_cursor_default=0; do
    grep -qw -- "$opt" /etc/kernel/cmdline || sed -i "s/\$/ $opt/" /etc/kernel/cmdline
done

# UKI: drop systemd-stub's own splash so only the Plymouth logo is shown
for p in /etc/mkinitcpio.d/*.preset; do
    cp -n "$p" "$p.before-plymouth"
    sed -i 's|^default_options="--splash [^"]*"|default_options=""|' "$p"
done

# systemd-boot: no menu by default
L=/boot/loader/loader.conf
cp -n $L $L.before-plymouth 2>/dev/null || touch $L
if grep -q '^timeout' $L; then sed -i 's/^timeout.*/timeout 0/' $L; else echo 'timeout 0' >> $L; fi
grep -q '^console-mode' $L || echo 'console-mode keep' >> $L

mkinitcpio -P
t "Готово. Перезагрузитесь, чтобы увидеть заставку." "Done. Reboot to see the splash."; echo
