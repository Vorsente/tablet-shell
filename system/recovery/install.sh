#!/bin/bash
# System snapshots + recovery. Run: sudo ./system/recovery/install.sh
#  - snapshot of the system before every pacman transaction (last 10 kept, /home not included)
#  - boot menu entry "до последнего обновления" (hold Space at power on to see the menu)
#  - snapshots visible read-only in /.snapshots; restore from the Settings app
source "$(dirname "$(readlink -f "$0")")/../common.sh"
SRC="$(dirname "$(readlink -f "$0")")"
# what this needs: btrfs root in subvolume @ (the Arch installer's layout), systemd-boot + UKI
[ "$(findmnt -no FSTYPE /)" = btrfs ] && findmnt -no OPTIONS / | grep -q 'subvol=/@\(,\|$\)' || {
    t "Нужен корень на btrfs в подтоме @: снимки не настроены." "Needs a btrfs root in subvolume @: snapshots not set up."; echo; exit 1; }
uki_boot || { t "Нужен systemd-boot с UKI: снимки не настроены." "Needs systemd-boot with a UKI: snapshots not set up."; echo; exit 1; }
pacman -S --needed --noconfirm btrfs-progs

install -Dm755 "$SRC/tablet-snapshot" /usr/local/lib/tablet/tablet-snapshot
ln -sf /usr/local/lib/tablet/tablet-snapshot /usr/local/bin/tablet-snapshot

# snapshot before every package transaction
install -d /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/00-tablet-snapshot.hook <<'HOOK'
[Trigger]
Operation = Upgrade
Operation = Install
Operation = Remove
Type = Package
Target = *

[Action]
Description = Снимок системы перед изменением пакетов…
When = PreTransaction
Exec = /usr/local/lib/tablet/tablet-snapshot create update
HOOK

# first snapshot now (also creates @snapshots and the rescue copy)
/usr/local/lib/tablet/tablet-snapshot create update

# snapshots readable in /.snapshots
UUID=$(findmnt -no UUID /)
mkdir -p /.snapshots
grep -q ' /.snapshots ' /etc/fstab || echo "UUID=$UUID	/.snapshots	btrfs	ro,noatime,subvol=/@snapshots	0 0" >> /etc/fstab
systemctl daemon-reload
mountpoint -q /.snapshots || mount /.snapshots

# boot menu entry for the copy taken before the last update (with its matching boot image)
cat > /boot/loader/entries/tablet-rescue.conf <<ENTRY
title   Arch Linux — до последнего обновления
efi     /EFI/Linux/arch-linux-rescue.efi
options $(sed -E 's/rootflags=subvol=@( |$)/rootflags=subvol=@rescue\1/' /etc/kernel/cmdline)
ENTRY
cat /boot/loader/entries/tablet-rescue.conf
ls /.snapshots
echo "Done."
