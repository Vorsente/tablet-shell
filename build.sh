#!/usr/bin/env bash
# Build independent tablet-shell components, preserving installed versions on failed updates.
# PREFIX=~/.local/share bash ./build.sh
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"
PREFIX=${PREFIX:-$HOME/.local/share}
OUT=build
mkdir -p "$OUT"
rm -rf -- "$OUT/.skipped"
mkdir -p "$OUT/.skipped"
rm -f -- "$OUT/.keyboard-reuse-installed"
if [[ "${TABLET_SHELL_EXCLUDE_INPUT_LOCK:-0}" == 1 ]]; then
    # Never let binaries left by an earlier build be mistaken for updated artifacts.
    rm -f -- "$OUT/tablet-keyboard" "$OUT/tablet-greeter"
    rm -rf -- "$OUT/sounds/keyboard"
fi
CXX=${CXX:-g++}
if [[ "$CXX" == g++ ]] && command -v ccache >/dev/null 2>&1; then CXX='ccache g++'; fi
CXXFLAGS=${CXXFLAGS:--std=c++20 -O2 -fPIC}
read -r -a compiler <<< "$CXX"
SKIP=${TABLET_SHELL_SKIP_FAILED_BUILDS:-0}
# Updates deliberately leave the existing keyboard and lock/login screens untouched.
EXCLUDE_INPUT_LOCK=${TABLET_SHELL_EXCLUDE_INPUT_LOCK:-0}
if [[ "$EXCLUDE_INPUT_LOCK" != 0 && "$EXCLUDE_INPUT_LOCK" != 1 ]]; then
    echo 'TABLET_SHELL_EXCLUDE_INPUT_LOCK must be 0 or 1' >&2; exit 2
fi
if [[ $SKIP != 0 && $SKIP != 1 ]]; then echo 'TABLET_SHELL_SKIP_FAILED_BUILDS must be 0 or 1' >&2; exit 2; fi

# A single whole-build cache entry is used ONLY for a completely successful build.
# Reused installed binaries must never be cached as newly built binaries.
CACHE_BASE="${XDG_CACHE_HOME:-$HOME/.cache}/tablet-shell/compiled"
CACHE_KEY=$( { printf '%s\n' "$PREFIX" "$CXX" "$CXXFLAGS";
    "${compiler[@]}" --version 2>/dev/null | head -1 || true
    pkg-config --modversion Qt6Core Qt6WaylandClient Qt6WebEngineQuick 2>/dev/null || true
    find src i18n -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.py' \) -print0 | sort -z | xargs -0 -r sha256sum
    sha256sum build.sh scripts/build-target.sh scripts/build-keyboard.sh shell/plasmoids/org.ipad.homescreen/contents/ui/shaders/weather.frag shell/plasmoids/org.ipad.homescreen/contents/ui/shaders/themed-icon.frag;
} | sha256sum | cut -d' ' -f1)
CACHE="$CACHE_BASE/$CACHE_KEY"
CACHE_BIN=(tabletd tablet-tools tabletshell tablet-settings tablet-keyboard tablet-greeter webapp-runner weather.frag.qsb themed-icon.frag.qsb en.json)
if [[ "$EXCLUDE_INPUT_LOCK" == 0 && -f "$CACHE/.complete" ]]; then
    valid=1
    for asset in "${CACHE_BIN[@]}"; do [[ -s "$CACHE/$asset" ]] || valid=0; done
    for dir in shell keyboard; do [[ -d "$CACHE/sounds/$dir" ]] || valid=0; done
    if ((valid)); then
        for asset in "${CACHE_BIN[@]}"; do cp -a -- "$CACHE/$asset" "$OUT/$asset"; done
        mkdir -p "$OUT/sounds"
        cp -a "$CACHE/sounds/." "$OUT/sounds/"
        printf '  %-18s %s\n' 'build cache' 'hit (complete build)'
        exit 0
    fi
fi

# What counts as a safe installed previous version. No known-good version => no silent skip.
installed_asset() {
    case "$1" in
        tabletd|tablet-tools) [[ -x "$PREFIX/tabletd/$1" ]] ;;
        tabletshell|tablet-settings|tablet-keyboard|tablet-greeter) [[ -x "$PREFIX/$1/$1" ]] ;;
        webapp-runner) [[ -x "$PREFIX/webapps/runner/webapp-runner" ]] ;;
        shaders) [[ -s "$PREFIX/plasma/plasmoids/org.ipad.homescreen/contents/ui/shaders/weather.frag.qsb" ]] ;;
        translations) [[ -s "$PREFIX/tablet-i18n/en.json" ]] ;;
        sounds-shell) compgen -G "$PREFIX/tabletshell/sounds/*.wav" >/dev/null ;;
        sounds-keyboard) compgen -G "$PREFIX/tablet-keyboard/sounds/*.wav" >/dev/null ;;
        *) return 1 ;;
    esac
}
artifact() {
    case "$1" in
      shaders) echo "$OUT/weather.frag.qsb" ;;
      translations) echo "$OUT/en.json" ;;
      sounds-shell) echo "$OUT/sounds/shell" ;;
      sounds-keyboard) echo "$OUT/sounds/keyboard" ;;
      *) echo "$OUT/$1" ;;
    esac
}
failed=()
skipped=()
# Translation builder copies Tr.js. It always runs first; a failure preserves installed translation.
for name in translations tabletd tablet-tools tabletshell tablet-settings tablet-keyboard tablet-greeter webapp-runner shaders sounds-shell sounds-keyboard; do
    if [[ "$EXCLUDE_INPUT_LOCK" == 1 ]]; then
        case "$name" in
            tablet-keyboard|tablet-greeter|sounds-keyboard)
                printf '  %-18s %s\n' "$name" 'untouched (excluded from update)'
                continue ;;
        esac
    fi
    printf '  %-18s ' "$name"
    target=$(artifact "$name")
    rm -rf -- "$target" # stale build artifacts must not be installed after a failed compile
    if PREFIX="$PREFIX" CXX="$CXX" CXXFLAGS="$CXXFLAGS" bash ./scripts/build-target.sh "$name" && [[ -e "$target" ]] && { [[ -d "$target" ]] || [[ -s "$target" ]]; }; then
        echo 'ok'
    else
        rm -rf -- "$target"
        if [[ $SKIP == 1 ]] && installed_asset "$name"; then
            : > "$OUT/.skipped/$name"
            skipped+=("$name")
            [[ "$name" != tablet-keyboard ]] || : > "$OUT/.keyboard-reuse-installed"
            printf 'SKIPPED — keeping installed version\n' >&2
        else
            failed+=("$name")
            printf 'FAILED — no safe installed fallback\n' >&2
        fi
    fi
done
if ((${#failed[@]})); then
    printf '\nBuild incomplete (not installed; no safe fallback): %s\n' "${failed[*]}" >&2
    exit 1
fi
if ((${#skipped[@]})); then
    printf '\nPARTIAL BUILD: kept installed components: %s\n' "${skipped[*]}" >&2
    exit 0
fi
# Excluded binaries are never written to or restored from a complete-build cache.
if [[ "$EXCLUDE_INPUT_LOCK" == 1 ]]; then exit 0; fi
# Cache only complete builds. Publish after all assets have been validated.
mkdir -p "$CACHE_BASE"
cache_temp=$(mktemp -d "$CACHE_BASE/.new-XXXXXXXX")
for asset in "${CACHE_BIN[@]}"; do cp -a -- "$OUT/$asset" "$cache_temp/$asset"; done
cp -a -- "$OUT/sounds" "$cache_temp/"
: > "$cache_temp/.complete"
if [[ ! -d "$CACHE" ]]; then mv -T -- "$cache_temp" "$CACHE"; else rm -rf -- "$cache_temp"; fi
