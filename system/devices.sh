#!/bin/bash
# Device access for the logged-in user (systemd-logind "uaccess": only the active seat's user):
#   uinput           tabletshell's virtual keys (back gesture, shortcuts)
#   power buttons    tabletd handles the power button and the Windows/home button under the screen
#   pens             tabletd: palm rejection, pen buttons, the corner quick note
#   touch screen     tabletshell: long press on text -> the phone-style text menu (read only)
#   keyboards        the typewriter's key sounds and the keyboard-dock detection
# Also installs the pen apps (Rnote, Xournal++).
# Run: sudo ./system/devices.sh            Undo: sudo ./system/devices.sh --undo
source "$(dirname "$(readlink -f "$0")")/common.sh"
RULES=/etc/udev/rules.d/70-tablet-shell.rules

if [ "${1:-}" = --undo ]; then
    rm -f "$RULES" /etc/modules-load.d/uinput.conf
    udevadm control --reload && udevadm trigger --subsystem-match=input --action=change
    exit 0
fi

pacman -S --needed --noconfirm rnote xournalpp

echo uinput > /etc/modules-load.d/uinput.conf
modprobe uinput
cat > "$RULES" <<'RULE'
# tablet-shell: device access for the user at the seat
KERNEL=="uinput", SUBSYSTEM=="misc", TAG+="uaccess", OPTIONS+="static_node=uinput"
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="Power Button", TAG+="uaccess"
SUBSYSTEM=="input", KERNEL=="event*", ATTRS{name}=="gpio-keys", TAG+="uaccess"
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_TABLET}=="1", TAG+="uaccess"
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_TOUCHSCREEN}=="1", TAG+="uaccess"
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", ENV{ID_BUS}=="usb|bluetooth", TAG+="uaccess"
RULE
# rules from older versions of this setup
rm -f /etc/udev/rules.d/70-tablet-input.rules /etc/udev/rules.d/70-tablet-power-button.rules /etc/udev/rules.d/70-tablet-uinput.rules
udevadm control --reload
udevadm trigger --subsystem-match=input --action=change
udevadm trigger --subsystem-match=misc --action=change
t "Готово." "Done."; echo
