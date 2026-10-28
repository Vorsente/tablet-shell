#!/bin/bash
# System snapshots + recovery. Run: sudo ./system/recovery/install.sh
#  - snapshot of the system before every pacman transaction (last 10 kept, /home not included)
#  - boot menu entry "до последнего обновления" (hold Space at power on to see the menu)
#  - snapshots visible read-only in /.snapshots; restore from the Settings app
source "$(dirname "$(readlink -f "$0")")/../common.sh"
SRC="$(dirname "$(readlink -f "$0")")"
# what this needs: a btrfs root. The tool and the snapshot index (Settings → Recovery lists every
# snapshot: this tool's, Snapper's, Timeshift's, other btrfs snapshots) work on any distribution;
# the own snapshots before updates, the rescue copy and its boot entry need Arch (a pacman hook),
# root in subvolume @ and systemd-boot + UKI. Snapper systems (openSUSE) keep their own.
[ "$(findmnt -no FSTYPE /)" = btrfs ] || {
    t "Корень не на btrfs: снимки не настроены." "The root is not on btrfs: snapshots not set up."; echo; exit 1; }
pkg_install btrfs-progs

install -Dm755 "$SRC/tablet-snapshot" /usr/local/lib/tablet/tablet-snapshot
ln -sf /usr/local/lib/tablet/tablet-snapshot /usr/local/bin/tablet-snapshot

# the index for Settings: refreshed when a snapshot directory changes (Snapper's /.snapshots,
# this tool's @snapshots mounted there on Arch) and every 15 minutes (Timeshift, others)
cat > /etc/systemd/system/tablet-snapshot-index.service <<'UNIT'
[Unit]
Description=Index of the system snapshots for Tablet Shell
ConditionPathExists=/usr/local/lib/tablet/tablet-snapshot

[Service]
Type=oneshot
Nice=10
IOSchedulingClass=idle
ExecStart=/usr/local/lib/tablet/tablet-snapshot scan
UNIT
cat > /etc/systemd/system/tablet-snapshot-index.path <<'UNIT'
[Unit]
Description=Watch the system snapshots for Tablet Shell

[Path]
PathChanged=/.snapshots
TriggerLimitIntervalSec=30
TriggerLimitBurst=4

[Install]
WantedBy=multi-user.target
UNIT
cat > /etc/systemd/system/tablet-snapshot-index.timer <<'UNIT'
[Unit]
Description=Refresh the snapshot index for Tablet Shell

[Timer]
OnBootSec=2min
OnUnitInactiveSec=15min

[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now tablet-snapshot-index.timer
[ -d /.snapshots ] && systemctl enable --now tablet-snapshot-index.path
/usr/local/lib/tablet/tablet-snapshot scan || true

# the rest are this tool's own snapshots: Arch with root in @ and systemd-boot + UKI
if [ "$PM" != pacman ] || ! findmnt -no OPTIONS / | grep -q 'subvol=/@\(,\|$\)' || ! uki_boot; then
    t "Снимки других средств видны в Настройках; свои снимки перед обновлениями — только на Arch (корень в @, systemd-boot + UKI)." \
      "Snapshots of other tools are listed in Settings; own snapshots before updates need Arch (root in @, systemd-boot + UKI)."; echo
    exit 0
fi

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
systemctl enable --now tablet-snapshot-index.path

# boot menu entry for the copy taken before the last update (with its matching boot image)
cat > /boot/loader/entries/tablet-rescue.conf <<ENTRY
title   Arch Linux — до последнего обновления
efi     /EFI/Linux/arch-linux-rescue.efi
options $(sed -E 's/rootflags=subvol=@( |$)/rootflags=subvol=@rescue\1/' /etc/kernel/cmdline)
ENTRY
cat /boot/loader/entries/tablet-rescue.conf
ls /.snapshots
echo "Done."
