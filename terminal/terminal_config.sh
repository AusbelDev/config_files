#!/bin/bash

set -euo pipefail

# Overridable defaults
NERD_FONT_VERSION="${NERD_FONT_VERSION:-v3.3.0}"

# Detect CI environment
IS_CI=false
if [ "${CI:-}" = "true" ]; then
    IS_CI=true
    export DEBIAN_FRONTEND=noninteractive
fi

# Colors
GREEN="\e[32m"
BLUE="\e[34m"
RED="\e[31m"
NC="\e[0m"

log() {
    echo -e "${GREEN}[+] $1${NC}"
}

info() {
    echo -e "${BLUE}[i] $1${NC}"
}

error() {
    echo -e "${RED}[!] $1${NC}" >&2
    exit 1
}

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -f, --full     Run full system package upgrade
  --no-nvim      Skip Neovim installation and configuration
  --no-fonts     Skip Nerd Font installation
  --no-exec      Do not replace current shell with 'exec zsh' at the end
  -h, --help     Show this help message

Environment variables:
  NERD_FONT_VERSION (default: ${NERD_FONT_VERSION})
EOF
}

# Parse options
RUN_FULL_UPGRADE=false
INSTALL_NVIM=true
INSTALL_FONTS=true
EXEC_ZSH=true
for arg in "$@"; do
    case "$arg" in
        -f|--full)
            RUN_FULL_UPGRADE=true
            ;;
        --no-nvim)
            INSTALL_NVIM=false
            ;;
        --no-fonts)
            INSTALL_FONTS=false
            ;;
        --no-exec)
            EXEC_ZSH=false
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            error "Unknown option: $arg (use --help for usage)"
            ;;
    esac
done

# Portable realpath helper (supports older macOS without GNU coreutils)
resolve_path() {
    if command -v realpath &>/dev/null; then
        realpath "$1"
    elif command -v python3 &>/dev/null; then
        python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
    else
        readlink -f "$1"
    fi
}

# Resolve script & dotfiles paths early (protects against symlinks and cwd changes)
REAL_SCRIPT_PATH="$(resolve_path "${BASH_SOURCE[0]}")"
DOTFILES_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")/.." && pwd)"

# Managed temp directory cleaned up on exit
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Ensure script is run as normal user, not root
if [ "$(id -u)" -eq 0 ]; then
    error "Do not run this script as root. It will use sudo as needed."
fi

# Detect OS & package manager
OS_TYPE="$(uname -s)"
PACKAGE_MANAGER=""
case "$OS_TYPE" in
    Linux*)
        if command -v apt &>/dev/null; then
            PACKAGE_MANAGER="apt"
        elif command -v dnf &>/dev/null; then
            PACKAGE_MANAGER="dnf"
        elif command -v pacman &>/dev/null; then
            PACKAGE_MANAGER="pacman"
        else
            error "Unsupported Linux distribution"
        fi
        ;;
    Darwin*)
        PACKAGE_MANAGER="brew"
        ;;
    *)
        error "Unsupported OS: $OS_TYPE"
        ;;
esac
log "Detected OS: $OS_TYPE, using package manager: $PACKAGE_MANAGER"

# Lazy apt cache refresh so fresh systems don't fail when --full isn't passed
APT_UPDATED=false
apt_update_once() {
    if [ "$APT_UPDATED" = false ]; then
        log "Updating apt package index..."
        sudo apt update
        APT_UPDATED=true
    fi
}

# Install package function
install_package() {
    case "$PACKAGE_MANAGER" in
        apt)
            if ! dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; then
                apt_update_once
                log "Installing $1..."
                sudo apt install -y "$1"
            else
                log "$1 already installed"
            fi
            ;;
        dnf)
            if ! rpm -q "$1" >/dev/null 2>&1; then
                log "Installing $1..."
                sudo dnf install -y "$1"
            else
                log "$1 already installed"
            fi
            ;;
        pacman)
            if ! pacman -Qs "^$1$" >/dev/null 2>&1; then
                log "Installing $1..."
                sudo pacman -S --noconfirm "$1"
            else
                log "$1 already installed"
            fi
            ;;
        brew)
            if ! brew list "$1" &>/dev/null; then
                log "Installing $1..."
                brew install "$1"
            else
                log "$1 already installed"
            fi
            ;;
    esac
}

# Update system
if [ "$IS_CI" = false ] && [ "$RUN_FULL_UPGRADE" = true ]; then
    log "Updating system..."
    case "$PACKAGE_MANAGER" in
        apt)
            apt_update_once
            sudo apt upgrade -y
            ;;
        dnf) sudo dnf upgrade -y ;;
        pacman) sudo pacman -Syu --noconfirm ;;
        brew) brew update && brew upgrade ;;
    esac
elif [ "$IS_CI" = false ]; then
    info "Skipping system package updates/upgrades (use --full or -f to update system)"
fi

# Helper to load Homebrew into PATH / GITHUB_PATH if present on Linux
BREW_SHELLENV_LINE=""
configure_linuxbrew_env() {
    local brew_bin=""
    if [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
        brew_bin="/home/linuxbrew/.linuxbrew/bin/brew"
        BREW_SHELLENV_LINE='eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
    elif [ -x "$HOME/.linuxbrew/bin/brew" ]; then
        brew_bin="$HOME/.linuxbrew/bin/brew"
        BREW_SHELLENV_LINE='eval "$($HOME/.linuxbrew/bin/brew shellenv)"'
    fi

    if [ -n "$brew_bin" ]; then
        eval "$("$brew_bin" shellenv)"
        if [ -n "${GITHUB_PATH:-}" ]; then
            echo "$(dirname "$brew_bin")" >> "$GITHUB_PATH"
        fi
        return 0
    fi
    return 1
}

# Install Homebrew if using apt (Linux)
if [ "$PACKAGE_MANAGER" = "apt" ]; then
    log "Checking for Homebrew..."
    if ! command -v brew &>/dev/null && ! configure_linuxbrew_env; then
        log "Installing Homebrew..."
        apt_update_once
        sudo apt install -y build-essential procps curl file git

        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        configure_linuxbrew_env || error "Homebrew installed but brew binary was not found."
    else
        configure_linuxbrew_env || true
        log "Homebrew already installed"
    fi
fi

# Install system packages (OS-dependent)
REQUIRED_PKGS=(zsh git curl unzip)
if [ "$PACKAGE_MANAGER" = "apt" ]; then
    REQUIRED_PKGS+=(fontconfig xclip)
fi

for pkg in "${REQUIRED_PKGS[@]}"; do
    install_package "$pkg"
done

# Install modern CLI tools
if command -v brew &>/dev/null; then
    log "Checking common tools with Homebrew..."
    BREW_PKGS=(lsd bat zoxide ripgrep git-delta fzf fd zellij)
    if [ "$INSTALL_NVIM" = true ]; then
        BREW_PKGS+=(neovim)
    else
        info "Skipping Neovim installation (--no-nvim)."
    fi

    INSTALLED_FORMULAE="$(brew list --formula 2>/dev/null || true)"
    MISSING_BREW_PKGS=()
    for pkg in "${BREW_PKGS[@]}"; do
        if grep -qxF "$pkg" <<< "$INSTALLED_FORMULAE"; then
            log "$pkg already installed"
        else
            MISSING_BREW_PKGS+=("$pkg")
        fi
    done

    if [ "${#MISSING_BREW_PKGS[@]}" -gt 0 ]; then
        log "Installing Homebrew packages: ${MISSING_BREW_PKGS[*]}..."
        brew install "${MISSING_BREW_PKGS[@]}"
    fi
elif [ "$PACKAGE_MANAGER" = "pacman" ]; then
    log "Installing common tools with pacman..."
    PACMAN_PKGS=(lsd bat zoxide ripgrep git-delta fzf fd zellij)
    if [ "$INSTALL_NVIM" = true ]; then
        PACMAN_PKGS+=(neovim)
    else
        info "Skipping Neovim installation (--no-nvim)."
    fi
    for pkg in "${PACMAN_PKGS[@]}"; do
        install_package "$pkg"
    done
elif [ "$PACKAGE_MANAGER" = "dnf" ]; then
    log "Installing common tools with dnf..."
    DNF_PKGS=(lsd bat zoxide ripgrep git-delta fzf fd-find)
    if [ "$INSTALL_NVIM" = true ]; then
        DNF_PKGS+=(neovim)
    else
        info "Skipping Neovim installation (--no-nvim)."
    fi
    for pkg in "${DNF_PKGS[@]}"; do
        install_package "$pkg" || info "Skipping unavailable dnf package: $pkg"
    done
fi

# Set zsh as default shell (skip in CI)
if [ "$IS_CI" = false ] && command -v zsh &>/dev/null; then
    CURRENT_USER="${USER:-$(whoami)}"
    if [ "$OS_TYPE" = "Darwin" ]; then
        LOGIN_SHELL="$(dscl . -read "/Users/$CURRENT_USER" UserShell 2>/dev/null | awk '{print $2}' || true)"
    else
        LOGIN_SHELL="$(getent passwd "$CURRENT_USER" 2>/dev/null | cut -d: -f7 || true)"
    fi
    CURRENT_SHELL="$(basename "${LOGIN_SHELL:-${SHELL:-}}")"
    ZSH_PATH="$(command -v zsh)"

    if [ "$CURRENT_SHELL" != "zsh" ]; then
        if [ -f /etc/shells ] && ! grep -qxF "$ZSH_PATH" /etc/shells; then
            info "$ZSH_PATH is not listed in /etc/shells; skipping chsh. Add it to /etc/shells and run 'chsh -s $ZSH_PATH' manually."
        else
            log "Setting Zsh as default shell..."
            chsh -s "$ZSH_PATH" "$CURRENT_USER" || info "Warning: Failed to change shell. Run 'chsh -s $ZSH_PATH' manually."
        fi
    fi
fi

# Configure FZF
if [ ! -f "$HOME/.fzf.zsh" ]; then
    if command -v brew &>/dev/null && [ -f "$(brew --prefix)/opt/fzf/install" ]; then
        "$(brew --prefix)/opt/fzf/install" --all --no-bash --no-fish
    fi
fi

# Install UV (non-interactive in CI)
if ! command -v uv >/dev/null 2>&1; then
    log "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# Ensure uv bin dirs are on PATH (and GITHUB_PATH for CI)
for uv_dir in "$HOME/.local/bin" "$HOME/.cargo/bin"; do
    if [ -d "$uv_dir" ]; then
        case ":$PATH:" in
            *":$uv_dir:"*) ;;
            *) export PATH="$uv_dir:$PATH" ;;
        esac
        if [ -n "${GITHUB_PATH:-}" ]; then
            echo "$uv_dir" >> "$GITHUB_PATH"
        fi
    fi
done

# Dotfiles helpers
link_config() {
    local src="$1"
    local dest="$2"
    local sync_back="${3:-true}"

    if [ ! -e "$src" ]; then
        info "Warning: Source $src does not exist. Skipping..."
        return 0
    fi

    mkdir -p "$(dirname "$dest")"

    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        info "$dest is already linked to $src"
        return 0
    fi

    # If destination is a regular file (not a symlink), optionally sync changes back to source
    if [ "$sync_back" = true ] && [ -f "$dest" ] && [ ! -L "$dest" ] && [ -f "$src" ]; then
        if ! cmp -s "$dest" "$src"; then
            log "Syncing modified file content from $dest back to $src"
            cp "$dest" "$src"
        fi
    fi

    # Backup if exists (and not the correct link)
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        local backup="${dest}.bak.$(date +%s)"
        log "Backing up existing $dest to $backup"
        mv "$dest" "$backup"
    fi

    log "Linking $src to $dest"
    ln -s "$src" "$dest"
}

render_template_file() {
    local src="$1"
    local dest="$2"
    local user_name="${USER:-$(whoami)}"

    if command -v python3 &>/dev/null; then
        python3 - "$src" "$dest" "$HOME" "$user_name" <<'PY'
import sys
src, dest, home, user = sys.argv[1:5]
with open(src, 'r') as f:
    content = f.read()
content = content.replace('{{HOME}}', home).replace('{{USER}}', user)
with open(dest, 'w') as f:
    f.write(content)
PY
    else
        local esc_home esc_user
        esc_home="$(printf '%s\n' "$HOME" | sed 's/[&/\]/\\&/g')"
        esc_user="$(printf '%s\n' "$user_name" | sed 's/[&/\]/\\&/g')"
        sed -e "s/{{HOME}}/${esc_home}/g" -e "s/{{USER}}/${esc_user}/g" "$src" > "$dest"
    fi
}

collapse_home_to_template() {
    local src="$1"
    local dest="$2"

    if command -v python3 &>/dev/null; then
        python3 - "$src" "$dest" "$HOME" <<'PY'
import sys
src, dest, home = sys.argv[1:4]
with open(src, 'r') as f:
    content = f.read()
content = content.replace(home, '{{HOME}}')
with open(dest, 'w') as f:
    f.write(content)
PY
    else
        local esc_home
        esc_home="$(printf '%s\n' "$HOME" | sed 's/[.[\*^$()+?{|/\\]/\\&/g')"
        sed -e "s/${esc_home}/{{HOME}}/g" "$src" > "$dest"
    fi
}

link_template_config() {
    local src="$1"
    local dest="$2"

    if [ ! -f "$src" ]; then
        info "Warning: Template $src does not exist. Skipping..."
        return 0
    fi

    mkdir -p "$(dirname "$dest")"

    # If destination exists as a regular file, sync changes back (collapsing HOME only)
    if [ -f "$dest" ] && [ ! -L "$dest" ]; then
        local temp_rendered="$TMP_DIR/rendered_$(basename "$src")"
        render_template_file "$src" "$temp_rendered"
        if ! cmp -s "$dest" "$temp_rendered"; then
            log "Syncing modified template config from $dest back to $src"
            collapse_home_to_template "$dest" "$src"
        fi
    fi

    if [ -L "$dest" ] || [ -d "$dest" ]; then
        local backup="${dest}.bak.$(date +%s)"
        log "Backing up existing $dest to $backup"
        mv "$dest" "$backup"
    fi

    log "Generating config from template $src to $dest"
    render_template_file "$src" "$dest"
}

setup_dotfiles() {
    log "Setting up dotfiles..."

    # Neovim Setup (Kickstart)
    if [ "$INSTALL_NVIM" = true ]; then
        if [ -L "$HOME/.config/nvim" ]; then
            rm "$HOME/.config/nvim"
        elif [ -d "$HOME/.config/nvim" ] && [ ! -d "$HOME/.config/nvim/.git" ]; then
            mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak.$(date +%s)"
        fi

        if [ ! -d "$HOME/.config/nvim" ]; then
            log "Cloning Kickstart.nvim..."
            git clone https://github.com/nvim-lua/kickstart.nvim.git "$HOME/.config/nvim"
        fi

        # Link custom init.lua without overwriting dotfiles repo with upstream kickstart's init.lua
        if [ -f "$DOTFILES_DIR/nvim/init.lua" ]; then
            link_config "$DOTFILES_DIR/nvim/init.lua" "$HOME/.config/nvim/init.lua" false
        fi
    else
        info "Skipping Neovim configuration (--no-nvim)."
    fi

    # Standard .config directories
    link_config "$DOTFILES_DIR/bat"    "$HOME/.config/bat"
    if command -v bat &>/dev/null && [ -d "$DOTFILES_DIR/bat" ]; then
        local bat_cache="${XDG_CACHE_HOME:-$HOME/.cache}/bat/themes.bin"
        if [ ! -f "$bat_cache" ]; then
            log "Building bat cache..."
            bat cache --build
        fi
    fi

    link_config "$DOTFILES_DIR/zellij" "$HOME/.config/zellij"
    link_config "$DOTFILES_DIR/git"    "$HOME/.config/git"

    # Gemini / Agy config linking
    mkdir -p "$DOTFILES_DIR/gemini/config"
    mkdir -p "$DOTFILES_DIR/gemini/plugins"
    link_template_config "$DOTFILES_DIR/gemini/settings.json" "$HOME/.gemini/antigravity-cli/settings.json"
    link_config "$DOTFILES_DIR/gemini/config"  "$HOME/.gemini/config"
    link_config "$DOTFILES_DIR/gemini/plugins" "$HOME/.gemini/antigravity-cli/plugins"

    # Initialize mcp_config.json template in dotfiles if it exists locally first
    if [ -f "$HOME/.gemini/antigravity-cli/mcp_config.json" ] && [ ! -f "$DOTFILES_DIR/gemini/mcp_config.json" ]; then
        log "Initializing mcp_config.json template in dotfiles from local file..."
        collapse_home_to_template "$HOME/.gemini/antigravity-cli/mcp_config.json" "$DOTFILES_DIR/gemini/mcp_config.json"
    fi

    if [ -f "$DOTFILES_DIR/gemini/mcp_config.json" ]; then
        link_template_config "$DOTFILES_DIR/gemini/mcp_config.json" "$HOME/.gemini/antigravity-cli/mcp_config.json"
    fi

    # P10k
    if [ -f "$DOTFILES_DIR/p10k/.p10k.zsh" ]; then
        link_config "$DOTFILES_DIR/p10k/.p10k.zsh" "$HOME/.p10k.zsh"
    fi
}

setup_dotfiles

# Setup antigravity statusline
setup_agy_statusline() {
    local cache_dir="$HOME/.cache"
    local statusline_repo="$cache_dir/antigravity-statusline"
    local target_repo="https://github.com/AusbelDev/antigravity-statusline.git"
    local statusline_installed_file="$HOME/.antigravity/status.py"

    mkdir -p "$cache_dir"

    if [ ! -d "$statusline_repo" ]; then
        log "Cloning antigravity-statusline..."
        git clone "$target_repo" "$statusline_repo"
        log "Running statusline installer..."
        (cd "$statusline_repo" && ./install.sh) || info "Warning: statusline installation failed"
    else
        log "Checking for antigravity-statusline updates..."
        (
            cd "$statusline_repo"
            local current_remote
            current_remote="$(git remote get-url origin 2>/dev/null || echo "")"
            if [ -n "$target_repo" ] && [ "$current_remote" != "$target_repo" ]; then
                log "Updating statusline remote origin to $target_repo..."
                git remote set-url origin "$target_repo"
            fi

            if git fetch origin &>/dev/null; then
                local local_hash remote_ref remote_hash
                local_hash="$(git rev-parse HEAD)"
                remote_ref="$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null \
                    || git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null \
                    || echo "origin/main")"
                remote_hash="$(git rev-parse "$remote_ref" 2>/dev/null \
                    || git rev-parse origin/master 2>/dev/null \
                    || echo "$local_hash")"

                if [ "$local_hash" != "$remote_hash" ] || [ ! -f "$statusline_installed_file" ]; then
                    log "Updating antigravity-statusline..."
                    git pull --ff-only || info "Warning: fast-forward pull failed for antigravity-statusline"
                    ./install.sh || info "Warning: statusline installation failed"
                else
                    log "Antigravity statusline is up to date"
                fi
            else
                info "Could not fetch statusline updates (offline?). Skipping update check."
                if [ ! -f "$statusline_installed_file" ]; then
                    log "Statusline not installed. Attempting installation..."
                    ./install.sh || info "Warning: statusline installation failed"
                fi
            fi
        )
    fi
}

setup_agy_statusline

# Sync back settings.json in case statusline installer updated it
if [ -f "$DOTFILES_DIR/gemini/settings.json" ]; then
    link_template_config "$DOTFILES_DIR/gemini/settings.json" "$HOME/.gemini/antigravity-cli/settings.json"
fi

# Symlink this script to ~/.local/bin/terminal-config
setup_script_command() {
    mkdir -p "$HOME/.local/bin"
    chmod +x "$REAL_SCRIPT_PATH"
    if [ ! -L "$HOME/.local/bin/terminal-config" ] || [ "$(readlink "$HOME/.local/bin/terminal-config")" != "$REAL_SCRIPT_PATH" ]; then
        log "Linking terminal-config command to ~/.local/bin/terminal-config..."
        rm -f "$HOME/.local/bin/terminal-config"
        ln -s "$REAL_SCRIPT_PATH" "$HOME/.local/bin/terminal-config"
    fi
}

setup_script_command

# Zap Zsh plugin manager
if [ ! -d "$HOME/.local/share/zap" ]; then
    log "Installing Zap..."
    zsh <(curl -fsSL https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1 --keep
fi

# Install Nerd Font (skip in CI or with --no-fonts)
if [ "$IS_CI" = false ] && [ "$INSTALL_FONTS" = true ]; then
    FONT_DIR="$HOME/.local/share/fonts"
    mkdir -p "$FONT_DIR"
    if [ "$PACKAGE_MANAGER" = "brew" ]; then
        if ! brew list --cask font-fira-mono-nerd-font &>/dev/null; then
            log "Installing FiraMono Nerd Font..."
            brew install --cask font-fira-mono-nerd-font
        else
            log "FiraMono Nerd Font already installed"
        fi
    else
        FONT_ZIP="FiraMono.zip"
        FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_FONT_VERSION}/${FONT_ZIP}"
        if [ ! -f "$FONT_DIR/FiraMonoNerdFont-Regular.ttf" ]; then
            log "Installing FiraMono Nerd Font (${NERD_FONT_VERSION})..."
            curl -fsSL -o "$TMP_DIR/$FONT_ZIP" "$FONT_URL"
            unzip -oq "$TMP_DIR/$FONT_ZIP" -d "$FONT_DIR"
            if command -v fc-cache &>/dev/null; then
                fc-cache -f "$FONT_DIR"
            fi
        else
            log "FiraMono Nerd Font already installed."
        fi
    fi
elif [ "$IS_CI" = true ]; then
    info "Skipping font installation in CI."
else
    info "Skipping font installation (--no-fonts)."
fi

# Manage a single ordered block in ~/.zshrc to avoid ordering drift across re-runs
update_zshrc_block() {
    local zshrc="$HOME/.zshrc"
    local start_marker="# >>> terminal_config managed block >>>"
    local end_marker="# <<< terminal_config managed block <<<"
    local block_file="$TMP_DIR/zshrc_block"
    local out_file="$TMP_DIR/zshrc_out"

    [ -f "$zshrc" ] || touch "$zshrc"
    cat > "$block_file"

    if grep -qF "$start_marker" "$zshrc" && grep -qF "$end_marker" "$zshrc"; then
        awk -v start="$start_marker" -v end="$end_marker" -v bf="$block_file" '
            $0 == start {
                print start
                while ((getline line < bf) > 0) print line
                close(bf)
                print end
                in_block = 1
                next
            }
            $0 == end { in_block = 0; next }
            !in_block { print }
        ' "$zshrc" > "$out_file"
    else
        cat "$zshrc" > "$out_file"
        {
            if [ -s "$out_file" ]; then echo ""; fi
            echo "$start_marker"
            cat "$block_file"
            echo "$end_marker"
        } >> "$out_file"
    fi

    cat "$out_file" > "$zshrc"
}

ZSH_BREW_PLUGIN_LINE=""
if command -v brew &>/dev/null; then
    ZSH_BREW_PLUGIN_LINE='plug "wintermi/zsh-brew"'
fi

log "Updating managed configuration block in ~/.zshrc..."
{
    if [ -n "$BREW_SHELLENV_LINE" ]; then
        printf '%s\n' "$BREW_SHELLENV_LINE"
    fi
    cat <<'EOF'
export PATH="$HOME/.local/bin:$PATH"
[ -d "$HOME/.cargo/bin" ] && export PATH="$HOME/.cargo/bin:$PATH"

# History settings
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
setopt sharehistory
setopt incappendhistory

# Zap Zsh plugin manager
[ -f "$HOME/.local/share/zap/zap.zsh" ] && source "$HOME/.local/share/zap/zap.zsh"

# Zap plugins (fzf-tab must load after supercharge/compinit, syntax-highlighting must load after fzf-tab)
plug "romkatv/powerlevel10k"
plug "wintermi/zsh-lsd"
EOF
    if [ -n "$ZSH_BREW_PLUGIN_LINE" ]; then
        printf '%s\n' "$ZSH_BREW_PLUGIN_LINE"
    fi
    cat <<'EOF'
plug "zap-zsh/supercharge"
plug "Aloxaf/fzf-tab"
plug "Freed-Wu/fzf-tab-source"
plug "zsh-users/zsh-autosuggestions"
plug "zsh-users/zsh-syntax-highlighting"
plug "zsh-users/zsh-history-substring-search"

# Aliases
alias clr="clear"
alias py="python3"
alias ls="lsd --group-directories-first -A"
alias ll="lsd -lA --group-directories-first --git"
alias lt="lsd -l --group-directories-first --tree --depth=2 --git"
alias gs="git status"
alias gcam="git commit -am"
alias gcm="git commit -m"
alias gpull="git pull"
alias gpush="git push"
alias gsw="git switch"
alias gst="git stash -m"
alias gstl="git stash list"
alias gsta="git stash apply"
alias gb="git branch"
alias gbr="git branch -r"
alias glog="git log --oneline --graph"

# Powerlevel10k config
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

# Machine-specific / private overrides
[[ ! -f ~/.zshrc.local ]] || source ~/.zshrc.local

# Zoxide initialization (must run at the very end after completion setup)
command -v zoxide &>/dev/null && eval "$(zoxide init zsh --cmd cd)"
EOF
} | update_zshrc_block

log "Setup complete!"
if [ "$IS_CI" = false ] && [ "$EXEC_ZSH" = true ] && [ -t 0 ] && [ -t 1 ]; then
    exec zsh
fi
