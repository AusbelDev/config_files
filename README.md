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

## 🛠 Installation

To set up your environment, clone this repository and run the setup script:

```bash
git clone https://github.com/ausbel/config_files.git ~/config_files
cd ~/config_files
chmod +x terminal/terminal_config.sh
./terminal/terminal_config.sh
```

The script will:
1. Detect your OS and install the necessary package managers (like Homebrew on Linux/macOS).
2. Install system-level dependencies and CLI tools.
3. Clone the Kickstart.nvim repository and link your custom configuration.
4. Set up symlinks for `bat`, `zellij`, `git`, and `p10k`.
5. Install Zap and configure Zsh plugins.

## 📂 Project Structure

- `terminal/terminal_config.sh`: The main bootstrap script.
- `nvim/`: Custom Neovim configuration (`init.lua`).
- `bat/`: Configuration and themes for `bat`.
- `zellij/`: Configuration for the Zellij terminal multiplexer.
- `git/`: Git configuration files.
- `p10k/`: Powerlevel10k configuration.
- `gemini/`: Gemini CLI settings.

## 🧪 CI/CD

This project uses GitHub Actions to verify the setup script on both Ubuntu and macOS environments, ensuring that all core commands and configurations are correctly installed and linked.
