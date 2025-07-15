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

check_cmd() {
    command -v "$1" >/dev/null 2>&1
}

add_zshrc_once() {
    grep -qxF "$1" "$HOME/.zshrc" || echo "$1" >> "$HOME/.zshrc"
}

install_package() {
    if ! dpkg -s "$1" >/dev/null 2>&1; then
        log "Installing $1..."
        sudo apt install -y "$1"
    else
        log "$1 already installed"
    fi
}

log "Updating system..."
sudo apt update && sudo apt upgrade -y

# Install required packages
for pkg in sudo wget curl zsh git lsd; do
    install_package "$pkg"
done

# Set zsh as default shell
if [ "$SHELL" != "/usr/bin/zsh" ]; then
    log "Setting Zsh as default shell..."
    chsh -s /usr/bin/zsh
fi

# Install FZF
if [ ! -d "$HOME/.fzf" ]; then
    log "Installing fzf..."
    git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
    ~/.fzf/install --key-bindings --completion --no-update-rc
fi
add_zshrc_once 'source ~/.fzf.zsh'

# History settings
add_zshrc_once 'HISTFILE=~/.zsh_history'
add_zshrc_once 'HISTSIZE=10000'
add_zshrc_once 'SAVEHIST=10000'
add_zshrc_once 'setopt appendhistory'

# Zap Zsh plugin manager
if [ ! -d "$HOME/.local/share/zap" ]; then
    log "Installing Zap..."
    zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1 --keep
fi
add_zshrc_once '[ -f "$HOME/.local/share/zap/zap.zsh" ] && source "$HOME/.local/share/zap/zap.zsh"'

# Zap plugins
add_zshrc_once 'plug "romkatv/powerlevel10k"'
add_zshrc_once 'plug "wintermi/zsh-lsd"'
add_zshrc_once 'plug "zsh-users/zsh-syntax-highlighting"'
add_zshrc_once 'plug "zsh-users/zsh-history-substring-search"'
add_zshrc_once 'plug "Aloxaf/fzf-tab"'

log "Setup complete! Starting Zsh..."
exec zsh
