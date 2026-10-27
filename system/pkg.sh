# Package installation on any distribution (sourced by install.sh and the system scripts).
# Packages are named as on Arch; pkg_names translates them for apt (Debian/Ubuntu), dnf (Fedora),
# zypper (openSUSE). An empty translation means "not packaged there / part of something else":
# it is skipped. Names that do not exist are reported and the rest are still installed.

PM=
for _pm in pacman apt-get dnf zypper; do command -v "$_pm" >/dev/null 2>&1 && { PM=$_pm; break; }; done
unset _pm

# pkg_names arch-name -> the distribution's package names (several, one, or none)
pkg_names() {
    local p=$1
    case $PM in
    pacman|"") echo "$p" ;;
    apt-get) case $p in
        base-devel) echo build-essential pkg-config ;;
        python) echo python3 ;;
        qt6-base) echo qt6-base-dev qt6-base-private-dev qt6-base-dev-tools qt6-qpa-plugins ;;
        qt6-declarative) echo qt6-declarative-dev qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-window qml6-module-qtquick-shapes qml6-module-qtqml-workerscript qml6-module-qt5compat-graphicaleffects ;;
        qt6-wayland) echo qt6-wayland-dev qt6-wayland-private-dev qt6-wayland-dev-tools qt6-wayland ;;
        qt6-multimedia) echo qt6-multimedia-dev qml6-module-qtmultimedia ;;
        qt6-multimedia-ffmpeg) echo libqt6multimedia6 ;;
        qt6-webengine) echo qt6-webengine-dev qml6-module-qtwebengine ;;
        qt6-shadertools) echo qt6-shader-baker qt6-shadertools-dev ;;
        qt6-tools) echo qt6-tools-dev-tools ;;
        wayland) echo libwayland-dev ;;
        kirigami) echo qml6-module-org-kde-kirigami libkf6kirigami-dev ;;
        kcmutils) echo libkf6kcmutils-dev ;;
        kconfig) echo libkf6config-dev ;;
        kcoreaddons) echo libkf6coreaddons-dev ;;
        kwindowsystem) echo libkf6windowsystem-dev ;;
        plasma5support) echo libplasma5support-dev ;;
        libksysguard) echo libksysguard-dev ;;
        layer-shell-qt) echo layer-shell-qt ;;
        libkscreen) echo libkscreen-bin ;;
        fd) echo fd-find ;;
        lazygit|tree-sitter-cli) ;;
        ttf-jetbrains-mono-nerd) echo fonts-jetbrains-mono ;;
        hunspell-en_us) echo hunspell-en-us ;;
        librsvg) echo librsvg2-bin ;;
        libpulse) echo libpulse0 ;;
        inter-font) echo fonts-inter ;;
        ttf-croscore) echo fonts-croscore ;;
        bluez-utils) echo bluez-tools ;;
        libinput-tools) echo libinput-tools ;;
        networkmanager) echo network-manager ;;
        btrfs-progs) echo btrfs-progs ;;
        python-pyclip) ;;
        *) echo "$p" ;;
        esac ;;
    dnf) case $p in
        base-devel) echo gcc-c++ make pkgconf-pkg-config ;;
        python) echo python3 ;;
        qt6-base) echo qt6-qtbase-devel qt6-qtbase-private-devel ;;
        qt6-declarative) echo qt6-qtdeclarative-devel qt6-qt5compat ;;
        qt6-wayland) echo qt6-qtwayland-devel ;;
        qt6-multimedia) echo qt6-qtmultimedia-devel ;;
        qt6-multimedia-ffmpeg) ;;
        qt6-webengine) echo qt6-qtwebengine-devel ;;
        qt6-shadertools) echo qt6-qtshadertools-devel ;;
        qt6-tools) echo qt6-qttools ;;
        wayland) echo wayland-devel ;;
        wayland-protocols) echo wayland-protocols-devel ;;
        kirigami) echo kf6-kirigami-devel ;;
        kcmutils) echo kf6-kcmutils-devel ;;
        kconfig) echo kf6-kconfig-devel ;;
        kcoreaddons) echo kf6-kcoreaddons-devel ;;
        kwindowsystem) echo kf6-kwindowsystem-devel ;;
        plasma5support) echo plasma5support-devel ;;
        libksysguard) echo libksysguard-devel ;;
        layer-shell-qt) echo layer-shell-qt-devel ;;
        fd) echo fd-find ;;
        lazygit) ;;
        ttf-jetbrains-mono-nerd) echo jetbrains-mono-fonts ;;
        hunspell-en_us) echo hunspell-en-US ;;
        librsvg) echo librsvg2-tools ;;
        libpulse) echo pulseaudio-libs ;;
        inter-font) echo rsms-inter-fonts ;;
        ttf-croscore) echo google-croscore-cousine-fonts ;;
        bluez-utils) echo bluez ;;
        libinput-tools) echo libinput-utils ;;
        networkmanager) echo NetworkManager ;;
        python-pyclip) ;;
        *) echo "$p" ;;
        esac ;;
    zypper) case $p in
        base-devel) echo gcc-c++ make pkgconf ;;
        python) echo python3 ;;
        qt6-base) echo qt6-base-devel qt6-base-private-devel ;;
        qt6-declarative) echo qt6-declarative-devel qt6-declarative-tools qt6-qt5compat-imports ;;
        qt6-wayland) echo qt6-wayland-devel qt6-wayland-private-devel ;;
        qt6-multimedia) echo qt6-multimedia-devel qt6-multimedia-imports ;;
        qt6-multimedia-ffmpeg) ;;
        qt6-webengine) echo qt6-webenginequick-devel ;;
        qt6-shadertools) echo qt6-shadertools qt6-shadertools-devel ;;
        qt6-tools) echo qt6-tools ;;
        wayland) echo wayland-devel ;;
        wayland-protocols) echo wayland-protocols-devel ;;
        kirigami) echo kf6-kirigami-devel ;;
        kcmutils) echo kf6-kcmutils-devel ;;
        kconfig) echo kf6-kconfig-devel ;;
        kcoreaddons) echo kf6-kcoreaddons-devel ;;
        kwindowsystem) echo kf6-kwindowsystem-devel ;;
        plasma-workspace) echo plasma6-workspace ;;
        plasma5support) echo plasma6-5support-devel ;;
        plasma-pa) echo plasma6-pa ;;
        plasma-mobile) echo plasma6-mobile ;;
        libksysguard) echo libksysguard6 ;;
        ksystemstats) echo ksystemstats6 ;;
        layer-shell-qt) echo layer-shell-qt6-devel ;;
        libkscreen) echo libkscreen6 ;;
        tree-sitter-cli) echo tree-sitter ;;
        ttf-jetbrains-mono-nerd) echo jetbrains-mono-fonts ;;
        hunspell-en_us) echo myspell-en_US ;;
        librsvg) echo rsvg-convert ;;
        libpulse) echo libpulse0 ;;
        inter-font) echo google-inter-fonts ;;
        ttf-croscore) echo google-cousine-fonts ;;
        bluez-utils) echo bluez ;;
        libinput-tools) echo libinput-tools ;;
        networkmanager) echo NetworkManager ;;
        python-pyclip) ;;
        *) echo "$p" ;;
        esac ;;
    esac
}

# installed? (by the distribution's own name)
pkg_have_native() {
    case $PM in
        pacman) pacman -Qq "$1" >/dev/null 2>&1 || pacman -Qqg "$1" >/dev/null 2>&1 ;;
        apt-get) dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed' ;;
        dnf|zypper) rpm -q --whatprovides "$1" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

# pkg_missing arch-names... -> the distribution's names that are not installed yet
pkg_missing() {
    local p n
    for p in "$@"; do
        for n in $(pkg_names "$p"); do pkg_have_native "$n" || echo "$n"; done
    done | awk '!seen[$0]++'
}

pkg_have() { [ -n "$PM" ] && [ -z "$(pkg_missing "$@")" ]; }

pkg_cmd() { # the command line (without sudo) that installs native names
    case $PM in
        pacman) echo pacman -S --needed --noconfirm "$@" ;;
        apt-get) echo apt-get install -y "$@" ;;
        dnf) echo dnf install -y "$@" ;;
        zypper) echo zypper --non-interactive install --no-recommends "$@" ;;
    esac
}

# pkg_install [--sudo] arch-names...   installs what is missing. Status 1 = some packages could
# not be installed (their names are printed); the rest are installed anyway.
pkg_install() {
    local sudo=() missing n failed=()
    [ "${1:-}" = --sudo ] && { sudo=(sudo); shift; }
    if [ -z "$PM" ]; then
        echo "  no known package manager (pacman/apt/dnf/zypper): install by hand: $*" >&2
        return 1
    fi
    mapfile -t missing < <(pkg_missing "$@")
    [ ${#missing[@]} -gt 0 ] || return 0
    # shellcheck disable=SC2046
    "${sudo[@]}" $(pkg_cmd "${missing[@]}") && return 0
    # one name unknown to this distribution must not block the others
    for n in "${missing[@]}"; do
        pkg_have_native "$n" && continue
        # shellcheck disable=SC2046
        "${sudo[@]}" $(pkg_cmd "$n") >/dev/null 2>&1 || failed+=("$n")
    done
    [ ${#failed[@]} -eq 0 ] && return 0
    echo "  not installed (not available here?): ${failed[*]}" >&2
    return 1
}
