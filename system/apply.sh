#!/bin/bash
# All system parts in one run, so the password is asked once: install.sh starts it with sudo, the
# Settings updater with pkexec (the KDE password dialog) before the update begins.
#   apply.sh --full [--greeter] [--android] [--no-greeter-refresh]
#                                             first install / reinstall: device access, Settings
#                                             wrappers, network + zram, system language, snapshots,
#                                             boot splash, own login screen (installed or refreshed)
#   apply.sh --update                         what an update may bring: device access (with what this
#                                             device needs: ThinkPad, Surface, others), Settings
#                                             wrappers, the new boot splash picture (keyboard and
#                                             login screen stay untouched)
#   --wait   authenticate now, run later: waits for a line "run" on stdin (anything else = quit)
# Each part runs on its own; one that fails or does not fit the machine (no btrfs, no UKI) is
# reported and the rest go on. One line per part on stdout: "PART <script> ok|skipped <label>".
# Logs: ~/.local/state/tablet-shell/system-*.log
source "$(dirname "$(readlink -f "$0")")/common.sh"
set +e

MODE= GREETER= ANDROID= WAIT= REFRESH=1
for arg in "$@"; do
    case "$arg" in
        --full) MODE=full ;;
        --update) MODE=update ;;
        --greeter) GREETER=1 ;;
        --android) ANDROID=1 ;;
        --no-greeter-refresh) REFRESH= ;;
        --wait) WAIT=1 ;;
        *) echo "unknown option: $arg" >&2; exit 2 ;;
    esac
done
[ -n "$MODE" ] || { echo "usage: apply.sh --full|--update [--greeter] [--android] [--wait]" >&2; exit 2; }

if [ -n "$WAIT" ]; then
    echo READY
    read -r go || exit 0
    [ "$go" = run ] || exit 0
fi

LOGS=$H/.local/state/tablet-shell
as_user mkdir -p "$LOGS"
FAILED=0
part() {   # part "русское имя" "english name" script [args...]
    local ru=$1 en=$2 script=$3; shift 3
    local log="$LOGS/system-$(echo "${script%.sh}" | tr / -).log"
    if SUDO_USER="$U" bash "$SYSTEM_DIR/$script" "$@" </dev/null >"$log" 2>&1; then
        echo "PART $script ok $(t "$ru" "$en")"
    else
        echo "PART $script skipped $(t "$ru" "$en")"
        grep -v '^\s*$' "$log" | tail -n 2 | sed 's/^/      /'
        FAILED=1
    fi
    chown "$U": "$log"
}

part "Доступ к кнопкам, перу, экрану" "Buttons, pen, touch access" devices.sh
part "«Настройки» вместо Параметров" "Settings instead of System Settings" settings-wrappers.sh
# an older boot splash (Arch logo with the device name) gets the new picture with updates too
if [ "$MODE" = update ] && grep -qs '^Theme=tablet-arch' /etc/plymouth/plymouthd.conf; then
    part "Заставка загрузки: новая картинка" "Boot splash: new picture" boot-splash/install.sh --theme-only
fi
if [ "$MODE" = full ]; then
    part "Сеть, Bluetooth, zram, приложения" "Network, Bluetooth, zram, apps" base.sh
    # the language Plasma already uses (plasma-localerc LANGUAGE, else the session's LANG)
    LANGCODE=$(as_user kreadconfig6 --file plasma-localerc --group Translations --key LANGUAGE 2>/dev/null)
    LANGCODE=${LANGCODE%%:*}
    [ -n "$LANGCODE" ] || LANGCODE=$(localectl status 2>/dev/null | sed -n 's/.*LANG=\([^.]*\).*/\1/p' | head -1)
    case "$LANGCODE" in
        ""|C|POSIX) ;;
        *) part "Язык системы ($LANGCODE)" "System language ($LANGCODE)" language.sh "$LANGCODE" ;;
    esac
    part "Снимки системы" "System snapshots" recovery/install.sh
    if grep -qs '^Theme=tablet-linux' /etc/plymouth/plymouthd.conf; then
        echo "PART boot-splash/install.sh ok $(t "Заставка загрузки (уже стоит)" "Boot splash (already set up)")"
    elif grep -qs '^Theme=tablet-arch' /etc/plymouth/plymouthd.conf; then
        part "Заставка загрузки: новая картинка" "Boot splash: new picture" boot-splash/install.sh --theme-only
    else
        part "Заставка загрузки" "Boot splash" boot-splash/install.sh
    fi
    [ -z "$ANDROID" ] || part "Android (Waydroid)" "Android (Waydroid)" android/install.sh
    if grep -Eqs 'tablet-greeter|tablet-shell-greeter' /etc/greetd/config.toml; then
        [ -z "$REFRESH" ] || part "Экран входа: обновление" "Login screen: refresh" greeter.sh --refresh
    elif [ -n "$GREETER" ]; then
        part "Экран входа" "Login screen" greeter.sh
    fi
fi
exit $FAILED
