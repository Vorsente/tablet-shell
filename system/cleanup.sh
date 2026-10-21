#!/bin/bash
# System cleanup: removes what this setup replaced or never uses. Keeps everything Plasma needs.
#   kup (backups -> btrfs snapshots), plasma-welcome, drkonqi (crash reporter); plasma-vault,
#   plasma-firewall, print-manager and flatpak only when unused (no vaults, no firewall service,
#   no CUPS, no flatpaks); plasma-login-manager only once the session was started by greetd (the
#   new login screen works); old package versions, coredumps.
# plasma-meta goes too, but its other packages are marked "explicitly installed" first, so a later
# orphan cleanup can never remove Plasma.
# Run: sudo ./system/cleanup.sh   (after the new login screen worked once)
source "$(dirname "$(readlink -f "$0")")/common.sh"
REMOVE=(kup plasma-welcome drkonqi)
# only what is not in use here
[ -z "$(ls -A /home/*/.local/share/plasma-vault 2>/dev/null)" ] && ! grep -q . "$H/.config/plasmavaultrc" 2>/dev/null && REMOVE+=(plasma-vault)
systemctl is-enabled -q firewalld.service ufw.service 2>/dev/null || REMOVE+=(plasma-firewall)
systemctl is-enabled -q cups.service cups.socket 2>/dev/null || REMOVE+=(print-manager)
command -v flatpak >/dev/null && [ -z "$(flatpak list 2>/dev/null)" ] && REMOVE+=(flatpak-kcm flatpak)

SESSION=$(loginctl list-sessions --no-legend | awk -v u="$U" '$3==u{print $1}' | head -1)
if [ -n "$SESSION" ] && [ "$(loginctl show-session "$SESSION" -p Service --value)" = "greetd" ]; then
    REMOVE+=(plasma-login-manager)
else
    t "plasmalogin оставлен: текущий сеанс ещё не через новый экран входа (перезагрузитесь и запустите снова)" \
      "plasmalogin kept: this session was not started by the new login screen (reboot and run again)"; echo
fi

if pacman -Q plasma-meta >/dev/null 2>&1; then
    KEEP=$(pacman -Qi plasma-meta | sed -n 's/^Depends On *: //p' | tr ' ' '\n' | sed 's/[<>=].*//' | grep -v '^None$' | grep -vxF -f <(printf '%s\n' "${REMOVE[@]}") || true)
    pacman -D --asexplicit $KEEP >/dev/null
    REMOVE+=(plasma-meta)
fi

INSTALLED=()
for p in "${REMOVE[@]}"; do pacman -Q "$p" >/dev/null 2>&1 && INSTALLED+=("$p"); done
[ ${#INSTALLED[@]} -gt 0 ] && pacman -Rns --noconfirm "${INSTALLED[@]}"

# orphans left behind (only packages nothing needs)
ORPHANS=$(pacman -Qdtq || true)
[ -n "$ORPHANS" ] && pacman -Rns --noconfirm $ORPHANS

# package cache: only the installed versions (btrfs snapshots cover rollbacks)
pacman -Sc --noconfirm >/dev/null
rm -f /var/lib/systemd/coredump/*
journalctl --vacuum-time=7d >/dev/null
echo
df -h / | tail -1
t "Готово." "Done."; echo
