#!/bin/bash

set -e  # Exit on error
set -u  # Treat unset variables as error

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
            sudo dnf install -y "$@"
            ;;
        pacman)
            sudo pacman -Sy --noconfirm "$@"
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
log "Updating system..."
case "$PACKAGE_MANAGER" in
    apt) sudo apt update && sudo apt upgrade -y ;;
    dnf) sudo dnf upgrade -y ;;
    pacman) sudo pacman -Syu --noconfirm ;;
    brew) brew update ;;
esac

# Install required packages
REQUIRED_PKGS=(zsh git curl unzip)
if [ "$PACKAGE_MANAGER" = "apt" ]; then
    REQUIRED_PKGS+=(lsd fontconfig bat ruby ruby-dev)
elif [ "$PACKAGE_MANAGER" = "brew" ]; then
    REQUIRED_PKGS+=(lsd bat ruby)
fi

for pkg in "${REQUIRED_PKGS[@]}"; do
    install_package "$pkg"
done

# Fix batcat on Debian
if [ "$PACKAGE_MANAGER" = "apt" ] && ! command -v bat &>/dev/null && command -v batcat &>/dev/null; then
    sudo ln -sf /usr/bin/batcat /usr/local/bin/bat
fi

# Set zsh as default shell
if [ "$SHELL" != "$(command -v zsh)" ]; then
    log "Setting Zsh as default shell..."
    chsh -s "$(command -v zsh)" "$USER"
fi

# Install FZF
if [ ! -d "$HOME/.fzf" ]; then
    log "Installing fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --all
fi
grep -qxF 'source <(fzf --zsh)' "$HOME/.zshrc" || echo 'source <(fzf --zsh)' >> "$HOME/.zshrc"

# History settings
add_zshrc_once() {
    grep -qxF "$1" "$HOME/.zshrc" || echo "$1" >> "$HOME/.zshrc"
}
add_zshrc_once 'HISTFILE=~/.zsh_history'
add_zshrc_once 'HISTSIZE=10000'
add_zshrc_once 'SAVEHIST=10000'
add_zshrc_once 'setopt appendhistory'
add_zshrc_once 'setopt sharehistory'
add_zshrc_once 'setopt incappendhistory'

# Aliases
add_zshrc_once 'alias clr="clear"'
add_zshrc_once 'alias py="python3"'
add_zshrc_once 'alias ls="ls -la"'
if command -v batcat &>/dev/null; then
    add_zshrc_once 'alias bat="batcat"'
fi

# Zap Zsh plugin manager
if [ ! -d "$HOME/.local/share/zap" ]; then
    log "Installing Zap..."
    zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1 --keep
fi
add_zshrc_once '[ -f "$HOME/.local/share/zap/zap.zsh" ] && source "$HOME/.local/share/zap/zap.zsh"'

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
)
for p in "${PLUGINS[@]}"; do add_zshrc_once "$p"; done

# Install Nerd Font
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
if [ "$PACKAGE_MANAGER" = "brew" ]; then
    brew tap homebrew/cask-fonts
    brew install --cask font-fira-mono-nerd-font
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

log "Setup complete! Starting Zsh..."
exec zsh
