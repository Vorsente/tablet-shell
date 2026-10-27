#!/bin/bash
# System language: generates the locale, makes it the system language (login screen, consoles),
# sets the user's Plasma language and formats, adds Firefox in that language and refreshes the
# login screen's translations. The shell itself is Russian or English (any other language shows
# English). Takes effect after logging in again.
# Run: sudo ./system/language.sh ru        (or: en, de, uk, ... ; a full locale like de_AT also works)
source "$(dirname "$(readlink -f "$0")")/common.sh"
ARG=${1:-}
[ -n "$ARG" ] || { echo "usage: sudo $0 ru|en|de|...|xx_YY"; exit 1; }
case "$ARG" in
    *_*) LOC=$ARG ;;
    en) LOC=en_US ;;
    uk) LOC=uk_UA ;;
    *) LOC=${ARG}_$(echo "$ARG" | tr a-z A-Z) ;;
esac
LANGCODE=${LOC%%_*}

# 1. the locale itself (en_US stays as the fallback)
# Arch, Debian, Gentoo generate locales from /etc/locale.gen; Fedora and openSUSE ship them in packages
if [ -f /etc/locale.gen ] && command -v locale-gen >/dev/null; then
    cp -n /etc/locale.gen /etc/locale.gen.before-tablet-shell
    for l in "$LOC" en_US; do
        sed -i "s/^#\s*\($l.UTF-8 UTF-8\)/\1/" /etc/locale.gen
    done
    locale-gen
else
    case $PM in
        dnf) pkg_install "glibc-langpack-$LANGCODE" || true ;;
        zypper) pkg_install glibc-locale || true ;;
    esac
fi
locale -a | grep -qi "^$LOC.utf8$" || { echo "$LOC.UTF-8: no such locale"; exit 1; }

# 2. system language: login screen, consoles, system messages
localectl set-locale LANG="$LOC.UTF-8"

# 3. the user's Plasma language and formats (dates, numbers, units)
as_user kwriteconfig6 --file plasma-localerc --group Formats --key LANG "$LOC.UTF-8"
if [ "$LANGCODE" = en ]; then
    as_user kwriteconfig6 --file plasma-localerc --group Translations --key LANGUAGE --delete
else
    as_user kwriteconfig6 --file plasma-localerc --group Translations --key LANGUAGE "$LANGCODE:en_US"
fi

# 4. Firefox in that language (a language pack per language on Arch and Debian; Fedora's
#    Firefox has them all, openSUSE has one package)
if [ "$LANGCODE" != en ] && command -v firefox >/dev/null; then
    case $PM in
        pacman) pkg_install "firefox-i18n-$LANGCODE" 2>/dev/null || pkg_install "firefox-i18n-$(echo "$LOC" | tr _ - )" 2>/dev/null ;;
        apt-get) pkg_install "firefox-l10n-$LANGCODE" 2>/dev/null || pkg_install "firefox-esr-l10n-$LANGCODE" 2>/dev/null ;;
        zypper) pkg_install MozillaFirefox-translations-common 2>/dev/null ;;
    esac || true
fi

# 5. the login screen's copy of the shell translations (if the own login screen is installed)
if [ -d /usr/local/share/tablet-greeter ]; then
    install -Dm644 -t /usr/local/share/tablet-greeter "$H/.local/share/tablet-greeter/Tr.js" "$H/.local/share/tablet-i18n/en.json"
    sed -i "s/LANG=[^ ]* cage/LANG=$LOC.UTF-8 cage/" /etc/greetd/config.toml 2>/dev/null || true
fi

t "Готово. Выйдите из сеанса и войдите снова (или перезагрузитесь)." "Done. Log out and back in (or reboot)."; echo
