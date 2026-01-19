#!/bin/bash

set -e  # Exit on error
set -u  # Treat unset variables as error

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

add_zshrc_once() {
    local zshrc="$HOME/.zshrc"
    [ -f "$zshrc" ] || touch "$zshrc"
    grep -qxF "$1" "$zshrc" || echo "$1" >> "$zshrc"
}

# 1. Environment Detection & Prep
# -----------------------------------------------------------------------------
OS_TYPE="$(uname -s)"
if [ "$OS_TYPE" != "Linux" ]; then
    error "This script is optimized for Linux (specifically Oracle Linux 8)."
fi

# Detect if running as root
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    SUDO="sudo"
    info "Running as non-root user. Using sudo for system commands."
else
    info "Running as root."
fi

# 2. System Packages (Oracle Linux 8 / RHEL 8)
# -----------------------------------------------------------------------------
log "Installing system dependencies..."

# Install EPEL for ripgrep, fd-find, etc.
if ! rpm -q epel-release >/dev/null 2>&1; then
    log "Enabling EPEL repository..."
    $SUDO dnf install -y epel-release
fi

# Enable CRB (Code Ready Builder) / PowerTools for some deps if needed (optional but good practice on RHEL8)
if command -v dnf &>/dev/null; then
    # Oracle Linux 8 usually enables necessary repos, but ensuring common build tools
    # util-linux-user is needed for 'chsh'
    # glibc-langpack-en is needed for locales in minimal containers
    REQUIRED_PKGS=(
        zsh git curl wget unzip tar
        util-linux-user glibc-langpack-en
        gcc make
        ripgrep fd-find fontconfig
    )
    
    log "Installing base packages..."
    $SUDO dnf install -y "${REQUIRED_PKGS[@]}"
fi

# Fix Locales (Common issue in minimal docker containers)
if command -v localedef &>/dev/null; then
    log "Generating locales..."
    $SUDO localedef -i en_US -f UTF-8 en_US.UTF-8 || true
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
fi

# 3. Modern Tool Installation (Binaries)
# -----------------------------------------------------------------------------
# We install binaries manually to get recent versions without Homebrew overhead

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"
add_zshrc_once 'export PATH="$HOME/.local/bin:$PATH"'

# --- Neovim ---
if ! command -v nvim &>/dev/null; then
    log "Installing Neovim via EPEL..."
    $SUDO dnf -y install ninja-build cmake gcc make gettext curl glibc-gconv-extra git
    git clone https://github.com/neovim/neovim && cd neovim && git checkout stable
    make CMAKE_BUILD_TYPE=RelWithDebInfo && $SUDO make install
    $SUDO mv /usr/local/bin/nvim $HOME/.local/bin/
else
    log "Neovim already installed."
fi

# --- Bat (Viewer) ---
if ! command -v bat &>/dev/null; then
    log "Installing Bat..."
    # Fetch latest release version for x86_64
    BAT_VERSION="0.24.0" # Pinned for stability, or use GitHub API to fetch latest
    BAT_RPM="bat-v${BAT_VERSION}-x86_64-unknown-linux-musl.tar.gz"
    BAT_URL="https://github.com/sharkdp/bat/releases/download/v${BAT_VERSION}/${BAT_RPM}"
    
    curl -fLo /tmp/bat.tar.gz "$BAT_URL"
    tar xzf /tmp/bat.tar.gz -C /tmp
    mv "/tmp/bat-v${BAT_VERSION}-x86_64-unknown-linux-musl/bat" "$BIN_DIR/"
    rm -rf /tmp/bat*
else
    log "Bat already installed."
fi

# --- LSD (Ls Deluxe) ---
if ! command -v lsd &>/dev/null; then
    log "Installing LSD..."
    LSD_VERSION="1.1.2"
    LSD_TAR="lsd-v${LSD_VERSION}-x86_64-unknown-linux-musl.tar.gz"
    LSD_URL="https://github.com/lsd-rs/lsd/releases/download/v${LSD_VERSION}/${LSD_TAR}"
    
    curl -fLo /tmp/lsd.tar.gz "$LSD_URL"
    tar xzf /tmp/lsd.tar.gz -C /tmp
    mv "/tmp/lsd-v${LSD_VERSION}-x86_64-unknown-linux-musl/lsd" "$BIN_DIR/"
    rm -rf /tmp/lsd*
else
    log "LSD already installed."
fi

# --- Zoxide (Smarter cd) ---
if ! command -v zoxide &>/dev/null; then
    log "Installing Zoxide..."
    curl -sS https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
else
    log "Zoxide already installed."
fi

# --- FZF ---
if [ ! -d "$HOME/.fzf" ]; then
    log "Installing FZF..."
    git clone --depth 1 https://github.com/junegunn/fzf.git "$HOME/.fzf"
    "$HOME/.fzf/install" --all --no-bash --no-fish
else
    log "FZF already installed."
fi

# 4. Dotfiles Configuration
# -----------------------------------------------------------------------------
DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

link_config() {
    local src="$1"
    local dest="$2"
    
    if [ ! -e "$src" ]; then
        info "Skipping missing source: $src"
        return
    fi
    mkdir -p "$(dirname "$dest")"
    
    if [ -L "$dest" ]; then rm "$dest"; fi
    if [ -e "$dest" ]; then mv "$dest" "${dest}.bak.$(date +%s)"; fi
    
    ln -s "$src" "$dest"
    log "Linked $dest -> $src"
}

# Fonts
log "Installing FiraCode font..."
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
if [ -f "$DOTFILES_DIR/Fonts/FiraCode.zip" ]; then
    unzip -o "$DOTFILES_DIR/Fonts/FiraCode.zip" -d "$FONT_DIR"
    if command -v fc-cache &>/dev/null; then
        fc-cache -f "$FONT_DIR"
    fi
else
    info "FiraCode.zip not found in $DOTFILES_DIR/Fonts/, skipping font installation."
fi

log "Setting up dotfiles..."

# Neovim Config
if [ ! -d "$HOME/.config/nvim" ]; then
    log "Cloning Kickstart.nvim..."
    git clone https://github.com/nvim-lua/kickstart.nvim.git "$HOME/.config/nvim"
    # Overwrite init.lua if it exists in dotfiles
    [ -f "$DOTFILES_DIR/nvim/init.lua" ] && link_config "$DOTFILES_DIR/nvim/init.lua" "$HOME/.config/nvim/init.lua"
fi

# Standard Configs
link_config "$DOTFILES_DIR/bat"    "$HOME/.config/bat"
if command -v bat &>/dev/null; then
    log "Building bat cache..."
    bat cache --build
fi
link_config "$DOTFILES_DIR/zellij" "$HOME/.config/zellij"
link_config "$DOTFILES_DIR/gemini" "$HOME/.config/gemini"

# P10k
[ -f "$DOTFILES_DIR/p10k/.p10k.zsh" ] && link_config "$DOTFILES_DIR/p10k/.p10k.zsh" "$HOME/.p10k.zsh"


# 5. Shell Configuration (Zsh + Zap)
# -----------------------------------------------------------------------------

# Change Shell
CURRENT_SHELL="$(basename "$SHELL")"
if [ "$CURRENT_SHELL" != "zsh" ] && command -v zsh &>/dev/null; then
    log "Changing default shell to zsh..."
    # chsh might require password or fail in some containers without PAM
    $SUDO chsh -s "$(command -v zsh)" "$(whoami)" || log "Warning: Failed to change shell. You may need to run 'chsh -s $(command -v zsh)' manually."
fi

# Zap Plugin Manager
if [ ! -d "$HOME/.local/share/zap" ]; then
    log "Installing Zap..."
    zsh <(curl -s https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1 --keep
fi

# Configure .zshrc
add_zshrc_once '[ -f "$HOME/.local/share/zap/zap.zsh" ] && source "$HOME/.local/share/zap/zap.zsh"'
add_zshrc_once 'eval "$(zoxide init zsh --cmd cd)"'

# Plugins
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

# Aliases
add_zshrc_once 'alias clr="clear"'
add_zshrc_once 'alias ls="lsd --group-directories-first -A"'
add_zshrc_once 'alias ll="lsd -lA --group-directories-first --git"'
add_zshrc_once 'alias lt="lsd -l --group-directories-first --tree --depth=2 --git"'
add_zshrc_once 'alias gs="git status"'
add_zshrc_once 'alias gcam="git commit -am"'
add_zshrc_once 'alias gpush="git push"'
add_zshrc_once 'autoload -Uz compinit && compinit -d "${ZDOTDIR:-$HOME}/.zcompdump"'
add_zshrc_once 'source ~/.p10k.zsh'

log "Setup complete! Please restart your shell or run 'zsh'."
