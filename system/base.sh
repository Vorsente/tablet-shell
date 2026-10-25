#!/bin/bash
# Base system for a small tablet: power profiles, Bluetooth, the touch-friendly KDE apps,
# NetworkManager (the Plasma network applet needs it), compressed RAM swap and smaller logs.
# Run: sudo ./system/base.sh
source "$(dirname "$(readlink -f "$0")")/common.sh"

say "Пакеты" "Packages"
pacman -S --needed --noconfirm power-profiles-daemon bluez bluez-utils alsa-utils libinput-tools networkmanager \
    gwenview okular haruna kate ark kcalc

# Network: Plasma's Wi-Fi applet talks to NetworkManager. Systems set up with systemd-networkd are
# switched over (with the iwd backend when iwd is what already holds the saved networks).
if systemctl is-enabled -q systemd-networkd.service 2>/dev/null && ! systemctl is-enabled -q NetworkManager.service 2>/dev/null; then
    say "Сеть: systemd-networkd → NetworkManager (после перезагрузки)" "Network: systemd-networkd → NetworkManager (after a reboot)"
    if systemctl is-enabled -q iwd.service 2>/dev/null; then
        mkdir -p /etc/NetworkManager/conf.d
        printf '[device]\nwifi.backend=iwd\n' > /etc/NetworkManager/conf.d/wifi_backend.conf
    fi
    systemctl disable systemd-networkd.service systemd-networkd.socket systemd-networkd-wait-online.service
fi
systemctl enable NetworkManager.service bluetooth.service power-profiles-daemon.service

# zram: all RAM as compressed swap, preferred over dropping page cache (helps a lot with 2-4 GB)
if pacman -Q zram-generator >/dev/null 2>&1 || pacman -S --needed --noconfirm zram-generator; then
    [ -f /etc/systemd/zram-generator.conf ] || printf '[zram0]\nzram-size = ram\ncompression-algorithm = zstd\n' > /etc/systemd/zram-generator.conf
    cat > /etc/sysctl.d/99-zram.conf <<'EOF'
vm.swappiness = 180
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.page-cluster = 0
EOF
fi


t "Готово. Перезагрузитесь." "Done. Reboot to apply."; echo
