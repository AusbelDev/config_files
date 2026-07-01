# Config Files / Dotfiles

A collection of configuration files and a setup script to bootstrap a productive development environment on Linux (Debian/Ubuntu/Fedora/Arch) and macOS.

## 🚀 Features

- **Shell:** Zsh with [Zap](https://github.com/zap-zsh/zap) plugin manager and [Powerlevel10k](https://github.com/romkatv/powerlevel10k) theme.
- **Editor:** Neovim configured with [Kickstart.nvim](https://github.com/nvim-lua/kickstart.nvim) as a base, with custom overrides.
- **Terminal Tools:**
  - `lsd`: A modern replacement for `ls`.
  - `bat`: A `cat` clone with syntax highlighting and Git integration.
  - `zoxide`: A smarter `cd` command.
  - `fzf`: A command-line fuzzy finder.
  - `zellij`: A terminal workspace with batteries included.
  - `uv`: Extremely fast Python package installer and resolver.
- **Fonts:** Includes FiraCode and MonoLisa Nerd Fonts.

## 🛠 Installation & Usage

To initially bootstrap your environment, clone this repository and run the setup script:

```bash
git clone https://github.com/ausbel/config_files.git ~/config_files
cd ~/config_files
chmod +x terminal/terminal_config.sh
./terminal/terminal_config.sh
```

### 💻 The `terminal-config` Command

Once installed, the bootstrap script registers itself as a global command. You can run it from any directory to check for updates or restore config files:

```bash
# Run a quick check for configuration updates and dotfiles health
terminal-config

# Run a full upgrade (includes system-level 'apt upgrade' / 'brew upgrade')
terminal-config --full
```

The script is fully idempotent: it checks if packages, symlinks, or updates are already present before performing any installations.

---

## 🤖 Gemini / Agy Configuration Sync

All settings, MCP registrations, custom skills, rules, and plugins are kept synchronized across your systems.

### 1. Settings & MCPs (`gemini/settings.json`)
* **Username Portability**: The `gemini/settings.json` file in this repository uses `{{HOME}}` and `{{USER}}` placeholders (e.g. `"cwd": "{{HOME}}/mcp-kimai/"`). The `terminal-config` tool dynamically compiles these placeholders for each machine's active environment.
* **Automatic Back-Syncing**: If you edit your settings locally or register new MCP servers, running `terminal-config` detects the local modifications, collapses the system paths back into `{{HOME}}`/`{{USER}}` templates, and saves the updates back into this repository automatically.

### 2. Global Customizations (`gemini/config/`)
The `gemini/config/` directory is mapped directly to `~/.gemini/config/`.
* Place your **custom rules** inside `gemini/config/AGENTS.md`.
* Place your **global agent skills** inside `gemini/config/skills/` (each folder must contain a `SKILL.md` file).

### 3. CLI Plugins (`gemini/plugins/`)
The `gemini/plugins/` directory is linked directly to `~/.gemini/antigravity-cli/plugins/`.
* Any namespaced plugin bundles (containing `plugin.json`, hooks, skills, and tools) can be stored here for portability.

### 4. Status Line Integration
The script automatically configures the [antigravity-statusline](https://github.com/60ke/antigravity-statusline.git) plugin. It tracks the upstream repository in `~/.cache/antigravity-statusline` and performs automatic updates and installations dynamically.

---

## 📂 Project Structure

- `terminal/terminal_config.sh`: The main bootstrap script (usable as `terminal-config`).
- `nvim/`: Custom Neovim configuration (`init.lua`).
- `bat/`: Configuration and themes for `bat`.
- `zellij/`: Configuration for the Zellij terminal multiplexer.
- `git/`: Git configuration files.
- `p10k/`: Powerlevel10k configuration.
- `gemini/settings.json`: Portability template for settings and MCP servers.
- `gemini/config/`: Global customization directory (skills, rules, etc.).
- `gemini/plugins/`: Plugins directory for namespaced CLI extensions.

## 🧪 CI/CD

This project uses GitHub Actions to verify the setup script on both Ubuntu and macOS environments, ensuring that all core commands and configurations are correctly installed and linked.
