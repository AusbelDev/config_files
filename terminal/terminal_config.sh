#!/bin/bash

set -e  # Exit on error
set -u  # Treat unset variables as error

# Detect CI environment
IS_CI=false
if [ "${CI:-}" = "true" ]; then
    IS_CI=true
    export DEBIAN_FRONTEND=noninteractive
fi

# Colors
GREEN="\e[32m"
RED="\e[31m"
NC="\e[0m"

log() {
    echo -e "${GREEN}[+] $1${NC}"
}

error() {
    echo -e "${RED}[!] $1${NC}" >&2
    exit 1
}

# Parse options
RUN_FULL_UPGRADE=false
for arg in "$@"; do
    case "$arg" in
        -f|--full)
            RUN_FULL_UPGRADE=true
            ;;
    esac
done

add_zshrc_once() {
    local zshrc="$HOME/.zshrc"
    [ -f "$zshrc" ] || touch "$zshrc"
    grep -qxF "$1" "$zshrc" || echo "$1" >> "$zshrc"
}

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

# Install package function
install_package() {
    case "$PACKAGE_MANAGER" in
        apt)
            if ! dpkg -s "$1" >/dev/null 2>&1; then
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
        apt) sudo apt update && sudo apt upgrade -y ;;
        dnf) sudo dnf upgrade -y ;;
        pacman) sudo pacman -Syu --noconfirm ;;
        brew) brew update && brew upgrade ;;
    esac
elif [ "$IS_CI" = false ]; then
    log "Skipping system package updates/upgrades (use --full or -f to update system)"
fi

# Install Homebrew if using apt (Linux)
if [ "$PACKAGE_MANAGER" = "apt" ]; then
    log "Checking for Homebrew..."
    if ! command -v brew &>/dev/null; then
        log "Installing Homebrew..."
        # Install dependencies for Homebrew
        sudo apt install -y build-essential procps curl file git
        
        # Install Homebrew
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
        
        # Configure shell environment
        if [ -d "/home/linuxbrew/.linuxbrew" ]; then
            eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
            add_zshrc_once 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'
            # Add to GITHUB_PATH for CI
            if [ -n "${GITHUB_PATH:-}" ]; then
                echo "/home/linuxbrew/.linuxbrew/bin" >> "$GITHUB_PATH"
            fi
        elif [ -d "$HOME/.linuxbrew" ]; then
            eval "$($HOME/.linuxbrew/bin/brew shellenv)"
            add_zshrc_once 'eval "$($HOME/.linuxbrew/bin/brew shellenv)"'
            # Add to GITHUB_PATH for CI
            if [ -n "${GITHUB_PATH:-}" ]; then
                echo "$HOME/.linuxbrew/bin" >> "$GITHUB_PATH"
            fi
        fi
    else
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

# Install common tools via Homebrew (Linux & macOS)
if command -v brew &>/dev/null; then
    log "Installing common tools with Homebrew..."
    BREW_PKGS=(lsd bat neovim zoxide ripgrep git-delta fzf fd)
    for pkg in "${BREW_PKGS[@]}"; do
        if ! brew list "$pkg" &>/dev/null; then
            log "Installing $pkg..."
            brew install "$pkg"
        else
            log "$pkg already installed"
        fi
    done
fi

# Set zsh as default shell (skip in CI)
if [ "$IS_CI" = false ] && [ "$(basename "$SHELL")" != "zsh" ]; then
    log "Setting Zsh as default shell..."
    chsh -s "$(command -v zsh)" "$USER"
fi

# Configure FZF (Already installed via brew)
if [ ! -f "$HOME/.fzf.zsh" ]; then
    # Homebrew fzf setup
    if command -v brew &>/dev/null && [ -f "$(brew --prefix)/opt/fzf/install" ]; then
        "$(brew --prefix)/opt/fzf/install" --all --no-bash --no-fish
    fi
fi

# Install UV (non-interactive in CI)
if ! command -v uv >/dev/null 2>&1; then
    log "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
    
    # Add to PATH for current script and GITHUB_PATH for CI
    if [ -d "$HOME/.cargo/bin" ]; then
        export PATH="$HOME/.cargo/bin:$PATH"
        if [ -n "${GITHUB_PATH:-}" ]; then
            echo "$HOME/.cargo/bin" >> "$GITHUB_PATH"
        fi
    elif [ -d "$HOME/.local/bin" ]; then
        export PATH="$HOME/.local/bin:$PATH"
        if [ -n "${GITHUB_PATH:-}" ]; then
            echo "$HOME/.local/bin" >> "$GITHUB_PATH"
        fi
    fi
fi

# Dotfiles Setup
REAL_SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}")"
DOTFILES_DIR="$(cd "$(dirname "$REAL_SCRIPT_PATH")/.." && pwd)"

link_config() {
    local src="$1"
    local dest="$2"
    
    # Check if source exists
    if [ ! -e "$src" ]; then
        log "Warning: Source file $src does not exist. Skipping..."
        return
    fi

    # Create parent dir if needed
    mkdir -p "$(dirname "$dest")"
    
    # Check if already linked correctly
    if [ -L "$dest" ]; then
        # Use ls -l to check link target efficiently across OS
        local link_target
        link_target="$(ls -ld "$dest" | awk '{print $NF}')"
        if [ "$link_target" = "$src" ]; then
            log "$dest is already linked to $src"
            return
        fi
    fi
    
    # If destination is a regular file (not a symlink), sync changes back to source
    if [ -f "$dest" ] && [ ! -L "$dest" ]; then
        if ! cmp -s "$dest" "$src"; then
            log "Syncing modified file content from $dest back to $src"
            cp "$dest" "$src"
        fi
    fi
    
    # Backup if exists (and not the correct link)
    if [ -e "$dest" ] || [ -L "$dest" ]; then
        log "Backing up existing $dest to ${dest}.bak"
        mv "$dest" "${dest}.bak"
    fi
    
    log "Linking $src to $dest"
    ln -s "$src" "$dest"
}

link_template_config() {
    local src="$1"
    local dest="$2"
    
    # Check if source exists
    if [ ! -e "$src" ]; then
        log "Warning: Source file $src does not exist. Skipping..."
        return
    fi

    # Create parent dir if needed
    mkdir -p "$(dirname "$dest")"
    
    # If destination exists, check if we need to sync back changes
    if [ -f "$dest" ] && [ ! -L "$dest" ]; then
        # Render src to a temporary file for comparison
        local temp_rendered
        temp_rendered=$(mktemp)
        python3 - "$src" "$temp_rendered" <<'PY'
import os, sys
with open(sys.argv[1], 'r') as f:
    c = f.read()
c = c.replace('{{HOME}}', os.environ['HOME']).replace('{{USER}}', os.environ['USER'])
with open(sys.argv[2], 'w') as f:
    f.write(c)
PY

        if ! cmp -s "$dest" "$temp_rendered"; then
            log "Syncing modified template config from $dest back to $src"
            # Collapse actual home/user back to placeholders
            python3 - "$dest" "$src" <<'PY'
import os, sys
with open(sys.argv[1], 'r') as f:
    c = f.read()
c = c.replace(os.environ['HOME'], '{{HOME}}').replace(os.environ['USER'], '{{USER}}')
with open(sys.argv[2], 'w') as f:
    f.write(c)
PY
        fi
        rm -f "$temp_rendered"
    fi
    
    # Backup if dest exists and is a symlink or directory
    if [ -L "$dest" ] || [ -d "$dest" ]; then
        log "Backing up existing $dest to ${dest}.bak"
        mv "$dest" "${dest}.bak"
    fi
    
    # Render the source template directly to the destination
    log "Generating config from template $src to $dest"
    python3 - "$src" "$dest" <<'PY'
import os, sys
with open(sys.argv[1], 'r') as f:
    c = f.read()
c = c.replace('{{HOME}}', os.environ['HOME']).replace('{{USER}}', os.environ['USER'])
with open(sys.argv[2], 'w') as f:
    f.write(c)
PY
}

setup_dotfiles() {
    log "Setting up dotfiles..."
    
    # Neovim Setup (Kickstart)
    if [ -L "$HOME/.config/nvim" ]; then
        rm "$HOME/.config/nvim"
    elif [ -d "$HOME/.config/nvim" ] && [ ! -d "$HOME/.config/nvim/.git" ]; then
        mv "$HOME/.config/nvim" "$HOME/.config/nvim.bak.$(date +%s)"
    fi
    
    if [ ! -d "$HOME/.config/nvim" ]; then
        log "Cloning Kickstart.nvim..."
        git clone https://github.com/nvim-lua/kickstart.nvim.git "$HOME/.config/nvim"
    fi
    
    # Link custom init.lua over the cloned one
    if [ -f "$DOTFILES_DIR/nvim/init.lua" ]; then
        log "Linking custom init.lua..."
        rm -f "$HOME/.config/nvim/init.lua"
        ln -s "$DOTFILES_DIR/nvim/init.lua" "$HOME/.config/nvim/init.lua"
    fi

    # Standard .config directories
    link_config "$DOTFILES_DIR/bat"    "$HOME/.config/bat"
    link_config "$DOTFILES_DIR/zellij" "$HOME/.config/zellij"
    link_config "$DOTFILES_DIR/git"    "$HOME/.config/git"
    
    # Gemini / Agy config linking
    mkdir -p "$DOTFILES_DIR/gemini/config"
    mkdir -p "$DOTFILES_DIR/gemini/plugins"
    link_template_config "$DOTFILES_DIR/gemini/settings.json" "$HOME/.gemini/antigravity-cli/settings.json"
    link_config "$DOTFILES_DIR/gemini/config"        "$HOME/.gemini/config"
    link_config "$DOTFILES_DIR/gemini/plugins"       "$HOME/.gemini/antigravity-cli/plugins"
    
    # Sync back and template mcp_config.json if it exists locally but not in dotfiles yet
    if [ -f "$HOME/.gemini/antigravity-cli/mcp_config.json" ] && [ ! -f "$DOTFILES_DIR/gemini/mcp_config.json" ]; then
        log "Initializing mcp_config.json template in dotfiles from local file..."
        python3 - "$HOME/.gemini/antigravity-cli/mcp_config.json" "$DOTFILES_DIR/gemini/mcp_config.json" <<'PY'
import os, sys
with open(sys.argv[1], 'r') as f:
    c = f.read()
c = c.replace(os.environ['HOME'], '{{HOME}}').replace(os.environ['USER'], '{{USER}}')
with open(sys.argv[2], 'w') as f:
    f.write(c)
PY
    fi

    if [ -f "$DOTFILES_DIR/gemini/mcp_config.json" ]; then
        link_template_config "$DOTFILES_DIR/gemini/mcp_config.json" "$HOME/.gemini/antigravity-cli/mcp_config.json"
    fi
    
    # P10k (usually in home)
    if [ -f "$DOTFILES_DIR/p10k/.p10k.zsh" ]; then
        link_config "$DOTFILES_DIR/p10k/.p10k.zsh" "$HOME/.p10k.zsh"
    fi
}

setup_dotfiles

# Setup antigravity statusline
setup_agy_statusline() {
    local cache_dir="$HOME/.cache"
    local statusline_repo="$cache_dir/antigravity-statusline"
    local statusline_installed_file="$HOME/.antigravity/status.py"
    
    mkdir -p "$cache_dir"
    
    if [ ! -d "$statusline_repo" ]; then
        log "Cloning antigravity-statusline..."
        git clone https://github.com/60ke/antigravity-statusline.git "$statusline_repo"
        log "Running statusline installer..."
        (cd "$statusline_repo" && ./install.sh)
    else
        log "Checking for antigravity-statusline updates..."
        (
            cd "$statusline_repo"
            if git fetch &>/dev/null; then
                local local_hash
                local_hash=$(git rev-parse HEAD)
                local remote_hash
                remote_hash=$(git rev-parse @{u} 2>/dev/null || echo "$local_hash")
                
                if [ "$local_hash" != "$remote_hash" ] || [ ! -f "$statusline_installed_file" ]; then
                    log "Updating antigravity-statusline..."
                    git pull
                    ./install.sh
                else
                    log "Antigravity statusline is up to date"
                fi
            else
                log "Could not fetch statusline updates (offline?). Skipping update check."
                if [ ! -f "$statusline_installed_file" ]; then
                    log "Statusline not installed. Attempting installation..."
                    ./install.sh || log "Warning: statusline installation failed"
                fi
            fi
        )
    fi
}

setup_agy_statusline

# Symlink this script to ~/.local/bin/terminal-config
setup_script_command() {
    mkdir -p "$HOME/.local/bin"
    local current_script
    current_script="$(realpath "${BASH_SOURCE[0]}")"
    chmod +x "$current_script"
    if [ ! -L "$HOME/.local/bin/terminal-config" ] || [ "$(readlink "$HOME/.local/bin/terminal-config")" != "$current_script" ]; then
        log "Linking terminal-config command to ~/.local/bin/terminal-config..."
        rm -f "$HOME/.local/bin/terminal-config"
        ln -s "$current_script" "$HOME/.local/bin/terminal-config"
    fi
}

setup_script_command
add_zshrc_once 'export PATH="$HOME/.local/bin:$PATH"'

# History settings
add_zshrc_once 'HISTFILE=~/.zsh_history'
add_zshrc_once 'HISTSIZE=10000'
add_zshrc_once 'SAVEHIST=10000'
add_zshrc_once 'setopt appendhistory'
add_zshrc_once 'setopt sharehistory'
add_zshrc_once 'setopt incappendhistory'

# Zap Zsh plugin manager
if [ ! -d "$HOME/.local/share/zap" ]; then
    log "Installing Zap..."
    zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1 --keep
fi
add_zshrc_once '[ -f "$HOME/.local/share/zap/zap.zsh" ] && source "$HOME/.local/share/zap/zap.zsh"'
add_zshrc_once 'eval "$(zoxide init zsh --cmd cd)"'
# Zap plugins
PLUGINS=(
    'plug "romkatv/powerlevel10k"'
    'plug "zap-zsh/supercharge"'
    'plug "wintermi/zsh-lsd"'
    'plug "zsh-users/zsh-syntax-highlighting"'
    'plug "zsh-users/zsh-history-substring-search"'
    'plug "Aloxaf/fzf-tab"'
    'plug "Freed-Wu/fzf-tab-source"'
    'plug "zsh-users/zsh-autosuggestions"'
    'plug "wintermi/zsh-brew"'
)
for p in "${PLUGINS[@]}"; do add_zshrc_once "$p"; done

# Install Nerd Font (skip in CI)
if [ "$IS_CI" = false ]; then
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
        FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/v3.0.2/$FONT_ZIP"
        if [ ! -f "$FONT_DIR/FiraMonoNerdFont-Regular.ttf" ]; then
            log "Installing FiraMono Nerd Font..."
            wget -q --show-progress -P "$FONT_DIR" "$FONT_URL"
            cd "$FONT_DIR"
            unzip -o "$FONT_ZIP"
            rm "$FONT_ZIP"
            fc-cache -fv
        else
            log "FiraMono Nerd Font already installed."
        fi
    fi
else
    log "Skipping font installation in CI."
fi

# Aliases
add_zshrc_once 'alias clr="clear"'
add_zshrc_once 'alias py="python3"'
add_zshrc_once 'alias ls="lsd --group-directories-first -A"'
add_zshrc_once 'alias ll="lsd -lA --group-directories-first --git"'
add_zshrc_once 'alias lt="lsd -l --group-directories-first --tree --depth=2 --git"'
add_zshrc_once 'alias gs="git status"'
add_zshrc_once 'alias gcam="git commit -am"'
add_zshrc_once 'alias gcm="git commit -m"'
add_zshrc_once 'alias gpull="git pull"'
add_zshrc_once 'alias gpush="git push"'
add_zshrc_once 'alias gsw="git switch"'
add_zshrc_once 'alias gst="git stash -m"'
add_zshrc_once 'alias gstl="git stash list"'
add_zshrc_once 'alias gsta="git stash apply"'
add_zshrc_once 'alias gb="git branch"'
add_zshrc_once 'alias gbr="git branch -r"'
add_zshrc_once 'alias glog="git log --oneline --graph"'
add_zshrc_once 'autoload -Uz compinit'
add_zshrc_once 'compinit -d "${ZDOTDIR:-$HOME}/.zcompdump"'
# Run dotfiles setup one more time to sync any overwritten settings files (e.g. settings.json updated by installers)
setup_dotfiles

log "Setup complete!"
if [ "$IS_CI" = false ]; then
    exec zsh
fi
