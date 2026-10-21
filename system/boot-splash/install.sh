#!/bin/bash
# Boot splash: a pulsing Arch logo with the device name, quiet boot, no boot menu (hold Space while
# powering on to get it). Needs systemd-boot with a unified kernel image (UKI) from mkinitcpio.
# Run: sudo ./system/boot-splash/install.sh     Undo: restore the *.before-plymouth files, mkinitcpio -P
source "$(dirname "$(readlink -f "$0")")/../common.sh"
SRC="$(dirname "$(readlink -f "$0")")"
uki_boot || { t "Нужен systemd-boot с UKI (mkinitcpio default_uki): не меняю загрузку." \
                "Needs systemd-boot with a UKI (mkinitcpio default_uki): boot left unchanged."; echo; exit 1; }

pacman -S --needed --noconfirm plymouth librsvg
T=/usr/share/plymouth/themes/tablet-arch
install -d "$T"
install -m644 "$SRC"/theme/* "$T/"
# the device's name under the logo (DMI; ThinkPads keep it in product_version)
MODEL=$(cat /sys/class/dmi/id/product_version 2>/dev/null)
case "$MODEL" in ""|*"System Version"*|*"To be filled"*|*Default*|*None*) MODEL=$(cat /sys/class/dmi/id/product_name 2>/dev/null) ;; esac
sed "s|@MODEL@|${MODEL:-Arch Linux}|" "$SRC/caption.svg" | rsvg-convert -o "$T/caption.png"
rm -rf /usr/share/plymouth/themes/thinkpad-arch     # older name of this theme

# DeviceScale=1: high-dpi tablet screens would otherwise double the images
cat > /etc/plymouth/plymouthd.conf <<'CONF'
[Daemon]
Theme=tablet-arch
ShowDelay=0
DeviceScale=1
CONF

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
