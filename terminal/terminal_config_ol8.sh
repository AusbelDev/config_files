#!/bin/bash

set -euo pipefail

# Pinned tool versions (overridable via environment variables)
NVIM_VERSION="${NVIM_VERSION:-stable}"
BAT_VERSION="${BAT_VERSION:-0.24.0}"
LSD_VERSION="${LSD_VERSION:-1.1.2}"
NVM_VERSION="${NVM_VERSION:-0.40.1}"
JIRA_HOST="${JIRA_HOST:-jira.jeppesensystems.com}"

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
  --no-nvim    Skip Neovim installation and configuration
  --no-node    Skip NVM and Node.js installation
  --no-ai      Skip Claude Code, Codex CLI, and Atlassian Jira MCP installation
  -h, --help   Show this help message

Environment variables:
  NVIM_VERSION (default: ${NVIM_VERSION})
  BAT_VERSION  (default: ${BAT_VERSION})
  LSD_VERSION  (default: ${LSD_VERSION})
  NVM_VERSION  (default: ${NVM_VERSION})
  JIRA_HOST    (default: ${JIRA_HOST})
  JIRA_TOKEN   (optional; required to configure Atlassian Jira MCP)
EOF
}

# Parse options
INSTALL_NVIM=true
INSTALL_NODE=true
INSTALL_AI=true
for arg in "$@"; do
    case "$arg" in
        --no-nvim)
            INSTALL_NVIM=false
            ;;
        --no-node)
            INSTALL_NODE=false
            ;;
        --no-ai)
            INSTALL_AI=false
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

# Resolve dotfiles directory early (handles symlinks and protects against cwd changes)
SCRIPT_PATH="$(realpath "${BASH_SOURCE[0]}" 2>/dev/null || readlink -f "${BASH_SOURCE[0]}")"
DOTFILES_DIR="$(cd "$(dirname "$SCRIPT_PATH")/.." && pwd)"

# Managed temp directory cleaned up on exit
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# 1. Environment Detection & Prep
# -----------------------------------------------------------------------------
OS_TYPE="$(uname -s)"
if [ "$OS_TYPE" != "Linux" ]; then
    error "This script is optimized for Linux (specifically Oracle Linux 8)."
fi

ARCH="$(uname -m)"
case "$ARCH" in
    x86_64)
        MUSL_ARCH="x86_64"
        NVIM_ARCH="x86_64"
        ;;
    aarch64|arm64)
        MUSL_ARCH="aarch64"
        NVIM_ARCH="arm64"
        ;;
    *)
        error "Unsupported architecture: $ARCH"
        ;;
esac

if ! command -v dnf &>/dev/null; then
    error "dnf is required (Oracle Linux 8 / RHEL 8)."
fi

# Detect if running as root
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo &>/dev/null; then
        error "sudo is required when running as a non-root user."
    fi
    SUDO="sudo"
    info "Running as non-root user. Using sudo for system commands."
else
    info "Running as root."
fi

# 2. System Packages (Oracle Linux 8 / RHEL 8)
# -----------------------------------------------------------------------------
log "Installing system dependencies..."

# Enable EPEL (Oracle Linux 8 ships oracle-epel-release-el8)
if ! rpm -q epel-release >/dev/null 2>&1 && ! rpm -q oracle-epel-release-el8 >/dev/null 2>&1; then
    log "Enabling EPEL repository..."
    if [ -f /etc/oracle-release ]; then
        $SUDO dnf install -y oracle-epel-release-el8 || $SUDO dnf install -y epel-release
    else
        $SUDO dnf install -y epel-release
    fi
fi

# util-linux-user is needed for 'chsh'
# glibc-langpack-en is needed for locales in minimal containers
# libatomic is needed by Node.js / native tooling on OL8
REQUIRED_PKGS=(
    zsh git curl unzip tar
    util-linux-user glibc-langpack-en libatomic
    gcc make
    ripgrep fd-find fontconfig
)

log "Installing base packages..."
$SUDO dnf install -y "${REQUIRED_PKGS[@]}"

# Fix Locales (Common issue in minimal docker containers)
if command -v localedef &>/dev/null; then
    if ! locale -a 2>/dev/null | grep -qi '^en_US\.utf-\?8$'; then
        log "Generating en_US.UTF-8 locale..."
        $SUDO localedef -i en_US -f UTF-8 en_US.UTF-8 || true
    fi
    export LANG=en_US.UTF-8
    export LC_ALL=en_US.UTF-8
fi

# 3. Modern Tool Installation (Binaries)
# -----------------------------------------------------------------------------
# We install binaries manually to get recent versions without Homebrew overhead

BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
export PATH="$BIN_DIR:$PATH"

# --- Neovim ---
install_neovim() {
    local nvim_tar="nvim-linux-${NVIM_ARCH}.tar.gz"
    local nvim_url="https://github.com/neovim/neovim/releases/download/${NVIM_VERSION}/${nvim_tar}"
    local prebuilt_dir="$TMP_DIR/nvim-prebuilt"

    mkdir -p "$prebuilt_dir"
    log "Downloading prebuilt Neovim (${NVIM_VERSION}, ${NVIM_ARCH})..."
    if curl -fsSL -o "$TMP_DIR/$nvim_tar" "$nvim_url" \
        && tar xzf "$TMP_DIR/$nvim_tar" -C "$prebuilt_dir" \
        && "$prebuilt_dir/nvim-linux-${NVIM_ARCH}/bin/nvim" --version &>/dev/null; then
        log "Installing prebuilt Neovim into $HOME/.local..."
        cp -rf "$prebuilt_dir/nvim-linux-${NVIM_ARCH}/." "$HOME/.local/"
        return 0
    fi

    info "Prebuilt Neovim binary unavailable or incompatible with system glibc; building from source..."
    $SUDO dnf install -y cmake gcc gcc-c++ make gettext curl git
    $SUDO dnf install -y ninja-build || info "ninja-build unavailable; falling back to Make."
    (
        git clone --depth 1 --branch "$NVIM_VERSION" https://github.com/neovim/neovim.git "$TMP_DIR/neovim"
        cd "$TMP_DIR/neovim"
        make -j"$(nproc)" CMAKE_BUILD_TYPE=RelWithDebInfo CMAKE_INSTALL_PREFIX="$HOME/.local"
        make install
    )
}

if [ "$INSTALL_NVIM" = true ]; then
    if ! command -v nvim &>/dev/null; then
        install_neovim
    else
        log "Neovim already installed."
    fi
else
    info "Skipping Neovim installation (--no-nvim)."
fi

# --- Bat (Viewer) ---
if ! command -v bat &>/dev/null; then
    log "Installing Bat ${BAT_VERSION} (${MUSL_ARCH})..."
    BAT_TAR="bat-v${BAT_VERSION}-${MUSL_ARCH}-unknown-linux-musl.tar.gz"
    BAT_URL="https://github.com/sharkdp/bat/releases/download/v${BAT_VERSION}/${BAT_TAR}"

    curl -fsSL -o "$TMP_DIR/$BAT_TAR" "$BAT_URL"
    tar xzf "$TMP_DIR/$BAT_TAR" -C "$TMP_DIR"
    mv "$TMP_DIR/bat-v${BAT_VERSION}-${MUSL_ARCH}-unknown-linux-musl/bat" "$BIN_DIR/"
else
    log "Bat already installed."
fi

# --- LSD (Ls Deluxe) ---
if ! command -v lsd &>/dev/null; then
    log "Installing LSD ${LSD_VERSION} (${MUSL_ARCH})..."
    LSD_TAR="lsd-v${LSD_VERSION}-${MUSL_ARCH}-unknown-linux-musl.tar.gz"
    LSD_URL="https://github.com/lsd-rs/lsd/releases/download/v${LSD_VERSION}/${LSD_TAR}"

    curl -fsSL -o "$TMP_DIR/$LSD_TAR" "$LSD_URL"
    tar xzf "$TMP_DIR/$LSD_TAR" -C "$TMP_DIR"
    mv "$TMP_DIR/lsd-v${LSD_VERSION}-${MUSL_ARCH}-unknown-linux-musl/lsd" "$BIN_DIR/"
else
    log "LSD already installed."
fi

# --- Zoxide (Smarter cd) ---
if ! command -v zoxide &>/dev/null; then
    log "Installing Zoxide..."
    curl -fsSL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | bash
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

# --- lnav (Log Viewer) ---
if ! command -v lnav &>/dev/null; then
    log "Installing lnav..."
    curl -fsSL https://packagecloud.io/install/repositories/tstack/lnav/script.rpm.sh | $SUDO bash
    $SUDO dnf install -y lnav
else
    log "lnav already installed."
fi

# --- Zellij (Terminal Multiplexer) ---
if ! command -v zellij &>/dev/null; then
    log "Installing Zellij (${MUSL_ARCH})..."
    ZELLIJ_URL="https://github.com/zellij-org/zellij/releases/latest/download/zellij-${MUSL_ARCH}-unknown-linux-musl.tar.gz"
    ZELLIJ_TMP="$TMP_DIR/zellij"
    mkdir -p "$ZELLIJ_TMP"
    curl -fsSL -o "$ZELLIJ_TMP/zellij.tar.gz" "$ZELLIJ_URL"
    tar xzf "$ZELLIJ_TMP/zellij.tar.gz" -C "$ZELLIJ_TMP"
    chmod +x "$ZELLIJ_TMP/zellij"
    mv "$ZELLIJ_TMP/zellij" "$BIN_DIR/"
else
    log "Zellij already installed."
fi

# --- NVM (Node Version Manager) & Node.js ---
export NVM_DIR="$HOME/.nvm"
if [ "$INSTALL_NODE" = true ]; then
    if [ ! -d "$NVM_DIR" ]; then
        log "Installing NVM v${NVM_VERSION}..."
        curl -fsSL "https://raw.githubusercontent.com/nvm-sh/nvm/v${NVM_VERSION}/install.sh" | bash
    else
        log "NVM already installed."
    fi

    # Load NVM for the current session to ensure Node LTS is installed
    if [ -s "$NVM_DIR/nvm.sh" ]; then
        set +u
        # shellcheck source=/dev/null
        \. "$NVM_DIR/nvm.sh"
        if [ "$(nvm version 'lts/*' 2>/dev/null || echo 'N/A')" = "N/A" ]; then
            log "Installing latest Node LTS version..."
            nvm install --lts
            nvm alias default 'lts/*'
        else
            log "Node LTS already installed ($(nvm version 'lts/*'))."
        fi
        nvm use --lts
        set -u
    else
        error "Failed to locate/load NVM."
    fi
else
    info "Skipping NVM and Node.js installation (--no-node)."
fi

# --- AI CLIs (Claude Code, Codex & Atlassian Jira MCP) ---
if [ "$INSTALL_AI" = true ]; then
    if ! command -v claude &>/dev/null; then
        log "Installing Claude Code CLI..."
        curl -fsSL https://claude.ai/install.sh | bash
    else
        log "Claude Code CLI already installed."
    fi

    if ! command -v codex &>/dev/null; then
        log "Installing Codex CLI..."
        curl -fsSL https://chatgpt.com/codex/install.sh | sh
    else
        log "Codex CLI already installed."
    fi

    # Install Atlassian Jira MCP
    if [ ! -d "$HOME/.atlassian-dc-mcp" ]; then
        if ! command -v npx &>/dev/null; then
            info "npx not available; skipping Atlassian Jira MCP installation."
        elif [ -z "${JIRA_TOKEN:-}" ]; then
            info "JIRA_TOKEN not set; skipping Atlassian Jira MCP installation."
        else
            log "Installing Atlassian Jira MCP..."
            npx -y @atlassian-dc-mcp/jira setup --non-interactive --host "$JIRA_HOST" --token "$JIRA_TOKEN"
            if command -v claude &>/dev/null; then
                claude mcp add-json atlassian-jira-dc '{"command":"npx","args":["-y","@atlassian-dc-mcp/jira"]}' --scope user
            fi
            if command -v codex &>/dev/null; then
                codex mcp add atlassian-jira-dc -- npx -y @atlassian-dc-mcp/jira
            fi
        fi
    else
        log "Atlassian Jira MCP already installed."
    fi
else
    info "Skipping AI CLI and MCP installations (--no-ai)."
fi

# 4. Dotfiles Configuration
# -----------------------------------------------------------------------------
link_config() {
    local src="$1"
    local dest="$2"

    if [ ! -e "$src" ]; then
        info "Skipping missing source: $src"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"

    if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
        info "$dest is already linked to $src"
        return 0
    fi

    if [ -L "$dest" ]; then
        rm "$dest"
    elif [ -e "$dest" ]; then
        mv "$dest" "${dest}.bak.$(date +%s)"
    fi

    ln -s "$src" "$dest"
    log "Linked $dest -> $src"
}

render_template_config() {
    local src="$1"
    local dest="$2"
    local user_name="${USER:-$(whoami)}"

    if [ ! -f "$src" ]; then
        info "Skipping missing template: $src"
        return 0
    fi
    mkdir -p "$(dirname "$dest")"

    if [ -L "$dest" ] || [ -d "$dest" ]; then
        mv "$dest" "${dest}.bak.$(date +%s)"
    fi

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
    log "Rendered template $dest from $src"
}

# Fonts
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
if [ -f "$FONT_DIR/FiraCodeNerdFont-Regular.ttf" ]; then
    log "FiraCode font already installed."
elif [ -f "$DOTFILES_DIR/Fonts/FiraCode.zip" ]; then
    log "Installing FiraCode font..."
    unzip -oq "$DOTFILES_DIR/Fonts/FiraCode.zip" -d "$FONT_DIR"
    if command -v fc-cache &>/dev/null; then
        fc-cache -f "$FONT_DIR"
    fi
else
    info "FiraCode.zip not found in $DOTFILES_DIR/Fonts/, skipping font installation."
fi

log "Setting up dotfiles..."

# Neovim Config
if [ "$INSTALL_NVIM" = true ]; then
    if [ ! -d "$HOME/.config/nvim" ]; then
        log "Cloning Kickstart.nvim..."
        git clone https://github.com/nvim-lua/kickstart.nvim.git "$HOME/.config/nvim"
    fi
    if [ -f "$DOTFILES_DIR/nvim/init.lua" ]; then
        link_config "$DOTFILES_DIR/nvim/init.lua" "$HOME/.config/nvim/init.lua"
    fi
else
    info "Skipping Neovim configuration (--no-nvim)."
fi

# Standard Configs
link_config "$DOTFILES_DIR/bat" "$HOME/.config/bat"
if command -v bat &>/dev/null && [ -d "$DOTFILES_DIR/bat" ]; then
    BAT_CACHE_FILE="${XDG_CACHE_HOME:-$HOME/.cache}/bat/themes.bin"
    if [ ! -f "$BAT_CACHE_FILE" ]; then
        log "Building bat cache..."
        bat cache --build
    fi
fi

link_config "$DOTFILES_DIR/git" "$HOME/.config/git"

if command -v zellij &>/dev/null; then
    link_config "$DOTFILES_DIR/zellij" "$HOME/.config/zellij"
else
    info "zellij not installed; skipping zellij config link."
fi

# Gemini / Antigravity CLI configs
if [ -d "$DOTFILES_DIR/gemini" ]; then
    render_template_config "$DOTFILES_DIR/gemini/settings.json" "$HOME/.gemini/antigravity-cli/settings.json"
    render_template_config "$DOTFILES_DIR/gemini/mcp_config.json" "$HOME/.gemini/antigravity-cli/mcp_config.json"
    link_config "$DOTFILES_DIR/gemini/config" "$HOME/.gemini/config"
    link_config "$DOTFILES_DIR/gemini/plugins" "$HOME/.gemini/antigravity-cli/plugins"
fi

# P10k
if [ -f "$DOTFILES_DIR/p10k/.p10k.zsh" ]; then
    link_config "$DOTFILES_DIR/p10k/.p10k.zsh" "$HOME/.p10k.zsh"
fi

# 5. Shell Configuration (Zsh + Zap)
# -----------------------------------------------------------------------------

# Change Shell
CURRENT_USER="$(whoami)"
LOGIN_SHELL="$(getent passwd "$CURRENT_USER" 2>/dev/null | cut -d: -f7 || true)"
CURRENT_SHELL="$(basename "${LOGIN_SHELL:-${SHELL:-}}")"
if [ "$CURRENT_SHELL" != "zsh" ] && command -v zsh &>/dev/null; then
    log "Changing default shell to zsh..."
    # chsh might require password or fail in some containers without PAM
    $SUDO chsh -s "$(command -v zsh)" "$CURRENT_USER" || log "Warning: Failed to change shell. You may need to run 'chsh -s $(command -v zsh)' manually."
fi

# Zap Plugin Manager
if [ ! -d "$HOME/.local/share/zap" ]; then
    log "Installing Zap..."
    zsh <(curl -fsSL https://raw.githubusercontent.com/zap-zsh/zap/master/install.zsh) --branch release-v1 --keep
fi

# Manage a single ordered block in ~/.zshrc to avoid ordering drift across re-runs
update_zshrc_block() {
    local zshrc="$HOME/.zshrc"
    local start_marker="# >>> terminal_config_ol8 managed block >>>"
    local end_marker="# <<< terminal_config_ol8 managed block <<<"
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

log "Updating managed configuration block in ~/.zshrc..."
update_zshrc_block <<'EOF'
export PATH="$HOME/.local/bin:$PATH"
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8

# History settings
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt appendhistory
setopt sharehistory
setopt incappendhistory

# NVM
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Zap Plugin Manager
[ -f "$HOME/.local/share/zap/zap.zsh" ] && source "$HOME/.local/share/zap/zap.zsh"

# Plugins (supercharge runs compinit; fzf-tab must load after it; syntax-highlighting after fzf-tab)
plug "romkatv/powerlevel10k"
plug "wintermi/zsh-lsd"
plug "zap-zsh/supercharge"
plug "Aloxaf/fzf-tab"
plug "Freed-Wu/fzf-tab-source"
plug "zsh-users/zsh-autosuggestions"
plug "zsh-users/zsh-syntax-highlighting"
plug "zsh-users/zsh-history-substring-search"

# Aliases
alias clr="clear"
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

# Machine-specific / private overrides (e.g. work aliases)
[[ ! -f ~/.zshrc.local ]] || source ~/.zshrc.local

# Zoxide (must run at the very end after completion setup)
command -v zoxide &>/dev/null && eval "$(zoxide init zsh --cmd cd)"
EOF

log "Setup complete! Please restart your shell or run 'zsh'."
