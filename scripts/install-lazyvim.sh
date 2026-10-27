#!/usr/bin/env bash
# Install LazyVim for tablet-shell without touching the user's default Neovim configuration.
# Called by install.sh (both initial installation and updates). No persistent logs.
set -euo pipefail

if (( EUID == 0 )); then
    echo 'Run the tablet-shell installer as the desktop user, not as root.' >&2
    exit 1
fi
for cmd in git nvim konsole; do
    command -v "$cmd" >/dev/null || { echo "Missing dependency: $cmd" >&2; exit 1; }
done

# LazyVim 15+ requires Neovim >= 0.11.2 (LuaJIT build).
nvim_version=$(nvim --version | sed -n '1s/^NVIM v\([0-9][0-9.]*\).*/\1/p')
if [[ -z "$nvim_version" ]] || [[ $(printf '%s\n' 0.11.2 "$nvim_version" | sort -V | head -n1) != 0.11.2 ]]; then
    echo "LazyVim requires Neovim 0.11.2 or later (found: ${nvim_version:-unknown})." >&2
    exit 1
fi
if ! nvim --version | grep -q 'LuaJIT'; then
    echo 'LazyVim requires a Neovim build with LuaJIT.' >&2
    exit 1
fi

config_root=${XDG_CONFIG_HOME:-$HOME/.config}
config="$config_root/tablet-shell-lazyvim"
mkdir -p -- "$config_root"
if [[ ! -e "$config" && ! -L "$config" ]]; then
    temp=$(mktemp -d "$config_root/.tablet-shell-lazyvim.XXXXXXXX")
    cleanup() { [[ -z "${temp:-}" ]] || rm -rf -- "$temp"; }
    trap cleanup EXIT
    # Clone into a temporary directory and rename when complete: never leave a half-installed config.
    if ! git clone --depth 1 --quiet https://github.com/LazyVim/starter.git "$temp/starter"; then
        echo 'Cannot fetch official LazyVim starter. Check the network and retry the installer.' >&2
        exit 1
    fi
    rm -rf -- "$temp/starter/.git" # official starter is user-configurable, not a linked git checkout
    mv -- "$temp/starter" "$config"
    cleanup
    trap - EXIT
fi
if [[ ! -f "$config/init.lua" ]]; then
    echo "Existing $config is not a LazyVim starter; left untouched. Resolve it manually." >&2
    exit 1
fi

# An independent config and data directory protects ~/.config/nvim and its plugins.
# A marker only follows successful installation; if interrupted, next install retries the sync.
marker="$config/.tablet-shell-plugins-ready"
if [[ ! -f "$marker" ]]; then
    echo 'Installing LazyVim plugins (first run needs GitHub access)...'
    if ! NVIM_APPNAME=tablet-shell-lazyvim nvim --headless '+Lazy! sync' '+qa' >/dev/null 2>&1; then
        echo 'LazyVim plugins could not be installed; retry ./install.sh when online.' >&2
        exit 1
    fi
    touch "$marker"
fi

# Tree-sitter parsers: LazyVim otherwise downloads and compiles ~25 of them the first time a file
# is opened (minutes on an Atom, the screen full of messages: it looked broken). Needs a C compiler
# and the tree-sitter CLI. Own marker, so earlier installs get them with the next update.
parsers="$config/.tablet-shell-parsers-ready"
if [[ ! -f "$parsers" ]]; then
    echo 'Installing the LazyVim tree-sitter parsers...'
    if NVIM_APPNAME=tablet-shell-lazyvim timeout 1800 nvim --headless "+lua local ok, err = pcall(function()
            local P = require('lazy.core.config').plugins['nvim-treesitter']
            local opts = require('lazy.core.plugin').values(P, 'opts', false)
            require('lazy').load({ plugins = { 'nvim-treesitter' } })
            local task = require('nvim-treesitter').install(opts.ensure_installed or {})
            if task and task.wait then task:wait(1700000) end
        end)
        if not ok then io.stderr:write(tostring(err) .. '\\n'); vim.cmd('cq') end
        vim.cmd('qa')" >/dev/null 2>&1; then
        touch "$parsers"
    else
        echo 'Tree-sitter parsers could not be installed (C compiler, tree-sitter CLI, network?); LazyVim will try on first use.' >&2
    fi
fi

# Own Konsole profile: no changes to the user's normal terminal or Apple/Pixel themes.
profile_dir="$HOME/.local/share/konsole"
mkdir -p -- "$profile_dir"
cat > "$profile_dir/TabletShellCoding.profile" <<'PROFILE'
[General]
Name=TabletShellCoding
Parent=FALLBACK/
[Appearance]
Font=JetBrainsMono Nerd Font,12,-1,5,50,0,0,0,0,0
PROFILE
printf 'LazyVim ready: %s\n' "$config"
