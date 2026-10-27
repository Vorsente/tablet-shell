# Shared by the system scripts (sourced, not run). They are started with sudo (or pkexec) by the user
# the shell is installed for: that user comes from SUDO_USER / PKEXEC_UID, never from a fixed name.
set -e
[ "$(id -u)" = 0 ] || { echo "run with sudo / запустите через sudo"; exit 1; }
U=${SUDO_USER:-}
# started through pkexec (the Settings updater asks for the password with the KDE dialog)
[ -n "$U" ] || [ -z "${PKEXEC_UID:-}" ] || U=$(id -nu "$PKEXEC_UID")
[ -n "$U" ] && [ "$U" != root ] || { echo "run with sudo from your own account / запустите через sudo из своей учётной записи"; exit 1; }
H=$(getent passwd "$U" | cut -d: -f6)
SYSTEM_DIR="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
source "$SYSTEM_DIR/pkg.sh"
as_user() { sudo -u "$U" env HOME="$H" "$@"; }

# messages in the user's language: t "русский" "english"
case "$(as_user kreadconfig6 --file plasma-localerc --group Translations --key LANGUAGE 2>/dev/null)${LANG:-}" in
    ru*) RU=1 ;; *) RU= ;;
esac
t() { if [ -n "$RU" ]; then printf '%s' "$1"; else printf '%s' "$2"; fi; }
say() { printf '== %s\n' "$(t "$1" "$2")"; }

# the boot setup the boot scripts expect: systemd-boot with unified kernel images (UKI) built by
# mkinitcpio from /etc/kernel/cmdline
uki_boot() {
    [ -f /etc/kernel/cmdline ] && [ -d /boot/loader ] && grep -q '^default_uki=' /etc/mkinitcpio.d/*.preset 2>/dev/null
}

# what kind of device this is, for the parts that differ: thinkpad10 | surface | other
device_profile() {
    local vendor product version
    vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null)
    product=$(cat /sys/class/dmi/id/product_name 2>/dev/null)
    version=$(cat /sys/class/dmi/id/product_version 2>/dev/null)
    case "$vendor|$product|$version" in
        LENOVO*"ThinkPad 10"*) echo thinkpad10 ;;
        Microsoft*"|Surface"*) echo surface ;;
        *) echo other ;;
    esac
}
