#!/usr/bin/env bash
# Upgrade an installed tablet-shell without reapplying themes or KDE preferences.
# With a Git checkout, fetch a fast-forward update first (unless --offline).
# For ZIP installations: ./update.sh --from /path/to/tablet-shell-new.zip
set -euo pipefail

# Visual stage indicator for terminal runs; stays plain when launched by Settings.
if [[ -t 1 && "${TERM:-dumb}" != dumb ]]; then
    COLOR=$'\033[38;5;111m'; BOLD=$'\033[1m'; MUTED=$'\033[2m'; RESET=$'\033[0m'
else
    COLOR=; BOLD=; MUTED=; RESET=
fi
stage() {
    local n=$1 label=$2
    printf '\n%s%s  tablet-shell  %s[%s/4]%s %s\n' "$BOLD" "$COLOR" "$RESET" "$n" "$RESET" "$label"
}

SELF_DIR=$(cd -- "$(dirname -- "$(readlink -f -- "$0")")" && pwd -P)
SOURCE="$SELF_DIR"
ARCHIVE=
FETCH=1
GREETER_ARGS=()
SKIP_FAILED_BUILDS=1

usage() {
    cat <<'USAGE'
Usage: ./update.sh [--offline] [--from ZIP_OR_DIRECTORY] [--require-all]

  ./update.sh                     Update a clean Git checkout (or reinstall local archive)
  ./update.sh --offline           Rebuild and reinstall this checkout without network fetch
  ./update.sh --from new.zip      Install a newer project ZIP without replacing user settings
  ./update.sh --from /path/dir    Install from another extracted project directory
  ./update.sh --no-greeter-update Compatibility option; login screen is never updated here
  ./update.sh --require-all       Stop if any UPDATABLE component fails to build
  ./update.sh --require-keyboard Deprecated; keyboard is always excluded from updates
  ./update.sh --keep-keyboard    Deprecated; keyboard is always excluded from updates

Must run as the desktop user (not root). On failure, the settings backup is retained.
USAGE
}

while (($#)); do
    case "$1" in
        --offline) FETCH=0 ;;
        --from)
            (($# >= 2)) && [[ -n "$2" ]] || { echo 'Missing value after --from' >&2; exit 2; }
            ARCHIVE=$2; shift ;;
        --no-greeter-update) : ;; # always protected in update-only mode
        --keep-keyboard|--require-keyboard)
            echo 'Note: keyboard and lock screen are excluded from every update.' >&2 ;;
        --require-all) SKIP_FAILED_BUILDS=0 ;;
        --skip-failed-builds) SKIP_FAILED_BUILDS=1 ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown argument: $1" >&2; usage >&2; exit 2 ;;
    esac
    shift
done

if (( EUID == 0 )); then
    echo 'Run ./update.sh as the desktop user, without sudo.' >&2
    exit 1
fi
[[ -x "$HOME/.local/share/tabletd/tabletd" ]] || {
    echo 'tablet-shell is not installed. Use ./install.sh first.' >&2
    exit 1
}
for bin in bash python3 rsync flock; do
    command -v "$bin" >/dev/null || { echo "Missing tool: $bin" >&2; exit 1; }
done

state="$HOME/.local/state/tablet-shell"
mkdir -p "$state"
exec {update_lock}>"$state/update.lock"
flock -n "$update_lock" || { echo 'Another tablet-shell update is in progress.' >&2; exit 1; }

tmp=
cleanup() { if [[ -n "$tmp" ]]; then rm -rf -- "$tmp"; fi; }
trap cleanup EXIT

stage 1 'Проверка источника / Source'
if [[ -n "$ARCHIVE" ]]; then
    [[ -e "$ARCHIVE" ]] || { echo "Update source not found: $ARCHIVE" >&2; exit 1; }
    if [[ -d "$ARCHIVE" ]]; then
        SOURCE=$(cd -- "$ARCHIVE" && pwd -P)
    else
        tmp=$(mktemp -d)
        # Validate ZIP paths, no symlinks, and bounded uncompressed size before extraction.
        SOURCE=$(python3 - "$ARCHIVE" "$tmp" <<'PY'
import pathlib, sys, zipfile
archive, root = sys.argv[1:]
with zipfile.ZipFile(archive) as z:
    entries = z.infolist()
    if len(entries) > 10000 or sum(i.file_size for i in entries) > 200 * 1024 * 1024:
        raise SystemExit('Archive is unexpectedly large')
    for i in entries:
        name = pathlib.PurePosixPath(i.filename)
        if i.filename.startswith('/') or '..' in name.parts or not i.filename or '\\' in i.filename:
            raise SystemExit('Unsafe path in update archive')
        if ((i.external_attr >> 16) & 0o170000) == 0o120000:
            raise SystemExit('Symbolic links are not accepted in update archive')
    z.extractall(root)
    top = pathlib.Path(root)
    dirs = [top / 'tablet-shell', top]
    matches = [d for d in dirs if (d / 'install.sh').is_file() and (d / 'build.sh').is_file()]
    if not matches:
        raise SystemExit('No tablet-shell/install.sh found in update archive')
    print(matches[0])
PY
        )
    fi
elif (( FETCH )) && git -C "$SELF_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    [[ -z "$(git -C "$SELF_DIR" status --porcelain --untracked-files=no)" ]] || {
        echo 'Working tree has local changes; refusing to overwrite them. Use --offline or --from.' >&2
        exit 1
    }
    upstream=$(git -C "$SELF_DIR" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)
    if [[ -n "$upstream" ]]; then
        echo 'Checking the tracked Git branch for updates...'
        git -C "$SELF_DIR" pull --ff-only
    else
        echo 'No upstream Git branch; rebuilding the local source.'
    fi
fi

[[ -f "$SOURCE/install.sh" && -f "$SOURCE/build.sh" && -f "$SOURCE/src/tabletd/tabletd.cpp" ]] || {
    echo "Not a tablet-shell source directory: $SOURCE" >&2
    exit 1
}

# Build all binaries first, while the running installation is still untouched.
stage 2 'Сборка / Build (Qt ABI cache enabled)'
printf '  Исходники / Sources: %s\n' "$SOURCE"
echo '  Keyboard + lock/login screen: excluded (no compile, no replacement)'
(cd -- "$SOURCE" && PREFIX="$HOME/.local/share" TABLET_SHELL_SKIP_FAILED_BUILDS="$SKIP_FAILED_BUILDS" \
    TABLET_SHELL_EXCLUDE_INPUT_LOCK=1 bash ./build.sh)
SKIPPED_COMPONENTS=()
if [[ -d "$SOURCE/build/.skipped" ]]; then
    for marker in "$SOURCE"/build/.skipped/*; do
        [[ -f "$marker" ]] || continue
        SKIPPED_COMPONENTS+=("$(basename "$marker")")
    done
fi
if ((${#SKIPPED_COMPONENTS[@]})); then
    printf '\nPARTIAL BUILD / ЧАСТИЧНАЯ СБОРКА: %s\n' "${SKIPPED_COMPONENTS[*]}" >&2
    echo 'Previous installed versions of these components will be retained.' >&2
fi
# Only installation-specific settings are backed up; these are not diagnostic logs.
stage 3 'Резервная копия / Backup'
backup=$(mktemp -d "$state/backup-XXXXXXXX")
mkdir -p "$backup/config" "$backup/systemd" "$backup/bin"
for config in plasma-org.kde.plasma.desktop-appletsrc tabletrc kwinrc kdeglobals; do
    if [[ -f "$HOME/.config/$config" ]]; then
        cp -a -- "$HOME/.config/$config" "$backup/config/"
    fi
done
for svc in tabletd.service tabletshell.service; do
    if [[ -f "$HOME/.config/systemd/user/$svc" ]]; then
        cp -a -- "$HOME/.config/systemd/user/$svc" "$backup/systemd/"
    fi
done
for app in tabletd tablet-tools; do
    if [[ -f "$HOME/.local/share/tabletd/$app" ]]; then
        cp -a -- "$HOME/.local/share/tabletd/$app" "$backup/bin/"
    fi
done

# Use a dedicated install mode: updates binaries, services, greeter (if already present),
# but does not reset KDE configuration, screen layout, theme, or weather city.
stage 4 'Установка / Install (settings preserved)'
if (cd -- "$SOURCE" && TABLET_SHELL_DOWNLOAD_ICONS=1 TABLET_SHELL_OFFLINE="$((1-FETCH))" bash ./install.sh --update-only --no-themes --no-build --no-greeter-update --skip-failed-builds); then
    if ((${#SKIPPED_COMPONENTS[@]})); then
        printf '\n\033[1;33mЧАСТИЧНОЕ ОБНОВЛЕНИЕ / PARTIAL UPDATE: skipped %s.\033[0m\n' "${SKIPPED_COMPONENTS[*]}" >&2
        printf 'Fix the build errors to update the skipped components. For strict mode: bash ./update.sh --offline --require-all\n' >&2
    else
        printf '\n%s✓ Обновление установлено. / Update installed.%s\n' "$COLOR" "$RESET"
    fi
    printf '%sРезервная копия / Backup:%s %s\n' "$MUTED" "$RESET" "$backup"
    printf 'Keyboard, lock screen and login screen were NOT updated.\n' 
else
    echo "Update was interrupted. Previous settings and daemon binaries: $backup" >&2
    exit 1
fi
