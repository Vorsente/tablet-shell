# Finds the Qt/KDE build tools and headers on any distribution (sourced, not run).
# Arch, Debian/Ubuntu, Fedora, openSUSE and others put moc, qtwaylandscanner, qsb and the
# KF6/Wayland/xkbcommon headers in different places; every value can still be forced from the
# environment (MOC=..., QTWS=..., QSB=..., KF6_INCLUDE=...).

# qmake/qtpaths know where this Qt build keeps its host tools.
qt_query() {
    local tool
    for tool in qtpaths6 qmake6 qtpaths qmake /usr/lib/qt6/bin/qtpaths6 /usr/lib64/qt6/bin/qtpaths6 \
                /usr/lib/qt6/bin/qmake /usr/lib64/qt6/bin/qmake /usr/lib/x86_64-linux-gnu/qt6/bin/qmake; do
        command -v "$tool" >/dev/null 2>&1 || continue
        # qmake5 answers too: only trust a Qt 6 one
        [[ "$("$tool" -query QT_VERSION 2>/dev/null)" == 6.* ]] || continue
        "$tool" -query "$1" 2>/dev/null && return 0
    done
    return 1
}

# first existing executable among: the Qt-reported dirs, the usual per-distro dirs, PATH
find_qt_tool() {
    local name=$1 dir
    local dirs=("$(qt_query QT_HOST_LIBEXECS || true)" "$(qt_query QT_HOST_BINS || true)"
                "$(qt_query QT_INSTALL_LIBEXECS || true)" "$(qt_query QT_INSTALL_BINS || true)"
                /usr/lib/qt6 /usr/lib/qt6/libexec /usr/lib/qt6/bin /usr/libexec/qt6 /usr/lib64/qt6/libexec
                /usr/lib64/qt6/bin /usr/lib/x86_64-linux-gnu/qt6/libexec /usr/lib/x86_64-linux-gnu/qt6/bin
                /usr/lib/aarch64-linux-gnu/qt6/libexec /usr/lib/aarch64-linux-gnu/qt6/bin)
    for dir in "${dirs[@]}"; do
        [[ -n "$dir" && -x "$dir/$name" ]] && { printf '%s\n' "$dir/$name"; return 0; }
    done
    for name in "$name"6 "$name"-qt6 "$name"; do
        command -v "$name" 2>/dev/null && return 0
    done
    return 1
}

MOC=${MOC:-$(find_qt_tool moc || echo moc)}
QTWS=${QTWS:-$(find_qt_tool qtwaylandscanner || echo qtwaylandscanner)}
QSB=${QSB:-$(find_qt_tool qsb || echo qsb)}

# KDE Frameworks 6 headers: <prefix>/include/KF6 next to the Qt headers on every distribution
# seen so far; /usr/local covers self-built frameworks.
if [[ -z "${KF6_INCLUDE:-}" ]]; then
    for KF6_INCLUDE in "$(qt_query QT_INSTALL_HEADERS 2>/dev/null)/../KF6" /usr/include/KF6 /usr/local/include/KF6; do
        [[ -d "$KF6_INCLUDE" ]] && break
    done
fi
KF6_INCLUDE=$(readlink -f "$KF6_INCLUDE" 2>/dev/null || echo /usr/include/KF6)
kf6() { # kf6 Module... -> -I flags for the module headers
    local m; for m in "$@"; do printf -- '-I%s/%s\n' "$KF6_INCLUDE" "$m"; done
}
# libraries outside the default linker path (e.g. a /usr/local KDE build)
KF6_LIBDIR=$(qt_query QT_INSTALL_LIBS 2>/dev/null || true)
KF6_LIB=(); [[ "$KF6_LIBDIR" == /usr/local/* || "$KF6_LIBDIR" == /opt/* ]] && KF6_LIB=(-L"$KF6_LIBDIR")
mapfile -t _kc < <(kf6 KConfigCore KConfig);                       KCONFIG=("${_kc[@]}" "${KF6_LIB[@]}" -lKF6ConfigCore)
mapfile -t _kc < <(kf6 KCMUtils KCMUtilsCore KCMUtilsQuick);       KCMUTILS=("${_kc[@]}" -lKF6KCMUtilsQuick -lKF6KCMUtilsCore)
mapfile -t _kc < <(kf6 KCoreAddons);                               KCOREADDONS=("${_kc[@]}" -lKF6CoreAddons)
mapfile -t _kc < <(kf6 KWindowSystem);                             KWINDOWSYSTEM=("${_kc[@]}" -lKF6WindowSystem)
unset _kc

# Wayland and xkbcommon headers live in subdirectories on some distributions
# (/usr/include/wayland, /usr/include/libxkbcommon); pkg-config knows where.
read -r -a WAYLAND_CFLAGS <<< "$(pkg-config --cflags wayland-client 2>/dev/null || true)"
read -r -a XKB_CFLAGS <<< "$(pkg-config --cflags xkbcommon 2>/dev/null || true)"

# package manager hint for error messages: pkg_hint arch-names...
pkg_hint() {
    local pm
    for pm in pacman apt-get dnf zypper xbps-install apk emerge; do command -v "$pm" >/dev/null 2>&1 && break; done
    case $pm in
        pacman) echo "sudo pacman -Syu $*" ;;
        apt-get) echo 'sudo apt install qt6-base-dev qt6-base-private-dev qt6-wayland-dev qt6-wayland-private-dev qt6-declarative-dev' ;;
        dnf) echo 'sudo dnf install qt6-qtbase-devel qt6-qtbase-private-devel qt6-qtwayland-devel qt6-qtdeclarative-devel' ;;
        zypper) echo 'sudo zypper install qt6-base-devel qt6-base-private-devel qt6-wayland-devel qt6-wayland-private-devel qt6-declarative-devel' ;;
        *) echo "install the Qt 6 base and Wayland development packages (with private headers): $*" ;;
    esac
}
