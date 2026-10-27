#!/bin/bash
# Device access for the logged-in user (systemd-logind "uaccess": only the active seat's user):
#   uinput           tabletshell's virtual keys (back gesture, shortcuts)
#   power buttons    tabletd handles the power button and the Windows/home button under the screen
#   pens             tabletd: palm rejection, pen buttons, the corner quick note
#   touch screen     tabletshell: long press on text -> the phone-style text menu (read only)
#   keyboards        the typewriter's key sounds and the keyboard-dock detection
#   tablet switch    tabletd: a 360° hinge / a Surface cover folded back means tablet mode
# Also installs the pen apps (Rnote, Xournal++).
# Run: sudo ./system/devices.sh            Undo: sudo ./system/devices.sh --undo
source "$(dirname "$(readlink -f "$0")")/common.sh"
RULES=/etc/udev/rules.d/70-tablet-shell.rules

if [ "${1:-}" = --undo ]; then
    rm -f "$RULES" /etc/modules-load.d/uinput.conf
    # what this particular device needs
case "$(device_profile)" in
    surface)
        # Surface Pro / Go / Book: touch and pen go through Intel IPTS, which needs the iptsd daemon
        # (linux-surface project; the type cover and the cover switch need its kernel modules)
        say "Surface: сенсорный экран и перо (iptsd)" "Surface: touch screen and pen (iptsd)"
        if ! pkg_have iptsd && ! pkg_install iptsd; then
            t "iptsd не найден в репозиториях: подключите репозиторий linux-surface (github.com/linux-surface/linux-surface/wiki/Installation-and-Setup), иначе касания и перо могут не работать." \
              "iptsd is not in the repositories: add the linux-surface repository (github.com/linux-surface/linux-surface/wiki/Installation-and-Setup), otherwise touch and pen may not work."; echo
        fi
        [ -d /sys/bus/surface_aggregator ] || { t "Модули Surface Aggregator не загружены: клавиатура-обложка может не определяться (ядро linux-surface)." \
            "Surface Aggregator modules are not loaded: the type cover may not be detected (linux-surface kernel)."; echo; }
        ;;
    thinkpad10)
        # ThinkPad 10: nothing extra (the Windows button, pen and dock are covered by the rules above)
        ;;
esac
udevadm control --reload && udevadm trigger --subsystem-match=input --action=change
    exit 0
fi

pkg_install rnote xournalpp || true   # optional pen apps

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
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_KEYBOARD}=="1", DEVPATH=="*/ssam:*", TAG+="uaccess"
# hinge / cover switch (SW_TABLET_MODE): tabletd switches tablet and PC mode by it
SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_SWITCH}=="1", TAG+="uaccess"
RULE
# rules from older versions of this setup
rm -f /etc/udev/rules.d/70-tablet-input.rules /etc/udev/rules.d/70-tablet-power-button.rules /etc/udev/rules.d/70-tablet-uinput.rules
udevadm control --reload
udevadm trigger --subsystem-match=input --action=change
udevadm trigger --subsystem-match=misc --action=change
t "Готово." "Done."; echo
