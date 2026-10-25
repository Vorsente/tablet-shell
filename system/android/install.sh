#!/bin/bash
# Android apps via Waydroid (an Android container on the Linux kernel).
# Run: sudo ./system/android/install.sh            plain Android, F-Droid as the app store
#  or: sudo ./system/android/install.sh --gapps    with Google Play (needs device registration)
# Then, as yourself: ./system/android/finish.sh
# On Intel/AMD tablets ARM-only apps need a translation layer: add --houdini (Intel) or --ndk (AMD).
source "$(dirname "$(readlink -f "$0")")/../common.sh"
grep -qw binder /proc/filesystems || modprobe binder_linux 2>/dev/null || {
    t "В ядре нет binder: Waydroid не запустится." "The kernel has no binder support: Waydroid cannot run."; echo; exit 1; }
pacman -S --needed --noconfirm waydroid python-pyclip wl-clipboard
case " $* " in *" --gapps "*) waydroid init -s GAPPS -f ;; *) waydroid init ;; esac
systemctl enable --now waydroid-container.service

# ARM translation (casualsnek/waydroid_script)
case " $* " in
    *" --houdini "*) LAYER=libhoudini ;;
    *" --ndk "*) LAYER=libndk ;;
    *) LAYER= ;;
esac
if [ -n "$LAYER" ]; then
    W=$(mktemp -d)
    git clone -q --depth 1 https://github.com/casualsnek/waydroid_script "$W/waydroid_script"
    python3 -m venv "$W/venv"
    "$W/venv/bin/pip" install -q -r "$W/waydroid_script/requirements.txt"
    "$W/venv/bin/python" "$W/waydroid_script/main.py" install "$LAYER"
    rm -rf "$W"
    systemctl restart waydroid-container.service
fi
t "Готово. Теперь без sudo: ./system/android/finish.sh" "Done. Now, without sudo: ./system/android/finish.sh"; echo
