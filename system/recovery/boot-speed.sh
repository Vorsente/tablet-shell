#!/bin/bash
# Faster boot on slow tablets:
#  - initramfs without hooks that do nothing here: fsck (btrfs needs none), keymap / consolefont
#    (only when no console keymap or font is configured); all other hooks (encryption, LVM ...) stay
#  - nothing waits for "network online"
#  - the Android container (if installed) starts a minute after boot instead of competing with it
# Run: sudo ./system/recovery/boot-speed.sh
# Undo: restore /etc/mkinitcpio.conf.before-bootspeed, mkinitcpio -P,
#       systemctl enable waydroid-container NetworkManager-wait-online, disable waydroid-container-late.timer
source "$(dirname "$(readlink -f "$0")")/../common.sh"
cp -n /etc/mkinitcpio.conf /etc/mkinitcpio.conf.before-bootspeed
drop=()
[ "$(findmnt -no FSTYPE /)" = btrfs ] && drop+=(fsck)
grep -qs '^KEYMAP=' /etc/vconsole.conf || drop+=(keymap)
grep -qs '^FONT=' /etc/vconsole.conf || drop+=(consolefont)
for h in "${drop[@]}"; do
    sed -i -E "/^HOOKS=/ s/ $h( |\))/\1/" /etc/mkinitcpio.conf
done
# an lz4 initramfs could not be unpacked by the kernel here (it booted without one): zstd
sed -i 's/^COMPRESSION="lz4"/COMPRESSION="zstd"/' /etc/mkinitcpio.conf
grep '^HOOKS' /etc/mkinitcpio.conf
mkinitcpio -P

systemctl disable NetworkManager-wait-online.service 2>/dev/null || true

if systemctl list-unit-files waydroid-container.service --no-legend | grep -q waydroid; then
    systemctl disable waydroid-container.service 2>/dev/null || true
    cat > /etc/systemd/system/waydroid-container-late.timer <<'TIMER'
[Unit]
Description=Start the Android container a minute after boot

[Timer]
OnBootSec=60
Unit=waydroid-container.service

[Install]
WantedBy=timers.target
TIMER
    systemctl daemon-reload
    systemctl enable waydroid-container-late.timer
fi
t "Готово." "Done."; echo
