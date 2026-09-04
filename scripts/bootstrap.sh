#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

echo "==> Validating system requirements..."

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "Error: This configuration currently supports Apple Silicon macOS only." >&2
  exit 1
fi

if [[ "$(id -un)" != "chhina" ]]; then
  echo "Error: This configuration expects the macOS account name 'chhina'." >&2
  exit 1
fi

# Ensure Xcode Command Line Tools are installed (required for Homebrew and native builds)
if ! xcode-select -p >/dev/null 2>&1; then
  echo "==> Xcode Command Line Tools not detected. Prompting installation..."
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  xcode-select --install 2>/dev/null || true
  echo "Waiting for Xcode Command Line Tools to complete installation..."
  until xcode-select -p >/dev/null 2>&1; do
    sleep 5
  done
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  echo "==> Xcode Command Line Tools installed."
fi

# Pre-flight migration checks for machines upgrading from older versions
echo "==> Running pre-flight migration checks..."

# Back up ~/.config/nvim if it is an existing directory (prevent Home Manager collision)
if [[ -d "${HOME}/.config/nvim" && ! -L "${HOME}/.config/nvim" ]]; then
  echo "==> Backing up existing ~/.config/nvim directory to ~/.config/nvim.before-nix..."
  mv "${HOME}/.config/nvim" "${HOME}/.config/nvim.before-nix"
fi

# Clean up broken symlinks across all managed paths to prevent Home Manager collisions
for link_path in \
  "${HOME}/.zshrc" "${HOME}/.zprofile" "${HOME}/.antigenrc" \
  "${HOME}/.ssh/config" "${HOME}/.gitconfig" "${HOME}/.p10k.zsh" "${HOME}/.zsh_aliases" "${HOME}/code/git.conf" \
  "${HOME}/.config/nvim" "${HOME}/.config/wezterm/wezterm.lua" "${HOME}/.config/herdr/config.toml" \
  "${HOME}/.config/git/personal.conf" "${HOME}/.config/git/ignore"; do
  if [[ -L "${link_path}" && ! -e "${link_path}" ]]; then
    echo "==> Removing stale broken symlink: ${link_path}"
    rm "${link_path}"
  fi
done

# Ensure strict SSH directory and file permissions
mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
if [[ -f "${repo_dir}/config/ssh/config" ]]; then
  chmod 600 "${repo_dir}/config/ssh/config"
fi
if ! command -v nix >/dev/null 2>&1 && [[ ! -x /nix/var/nix/profiles/default/bin/nix ]]; then
  echo ""
  read -r -p "Determinate Nix is not installed. Install it now? [y/N] " answer
  if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
    echo "Install Determinate Nix, then run this script again." >&2
    exit 1
  fi

  echo "==> Installing Determinate Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install
fi

# Ensure Nix environment is active in the current process
if [[ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]]; then
  # shellcheck disable=SC1091
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

if [[ -d /nix/var/nix/profiles/default/bin ]]; then
  export PATH="/nix/var/nix/profiles/default/bin:${PATH}"
fi

echo "==> Handing off to rebuild script..."
exec "${repo_dir}/scripts/rebuild.sh"
