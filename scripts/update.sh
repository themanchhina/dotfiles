#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

# Source Nix profile if available in standard location
if [[ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]]; then
  # shellcheck disable=SC1091
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

if command -v nix >/dev/null 2>&1; then
  nix_bin="$(command -v nix)"
elif [[ -x /nix/var/nix/profiles/default/bin/nix ]]; then
  nix_bin="/nix/var/nix/profiles/default/bin/nix"
else
  echo "Error: Nix is not installed. Run ${repo_dir}/scripts/bootstrap.sh first." >&2
  exit 1
fi

# Ensure untracked files are staged for Nix
if git -C "${repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  untracked="$(git -C "${repo_dir}" ls-files --others --exclude-standard)"
  if [[ -n "${untracked}" ]]; then
    git -C "${repo_dir}" add -N .
  fi
fi

if [[ -x /opt/homebrew/bin/brew ]]; then
  echo "==> Updating Homebrew formula and cask indexes..."
  /opt/homebrew/bin/brew update
fi

echo "==> Updating Nix flake inputs..."
"${nix_bin}" flake update --flake "path:${repo_dir}"

echo "==> Rebuilding system..."
"${repo_dir}/scripts/rebuild.sh"

if [[ -x /opt/homebrew/bin/brew ]]; then
  echo "==> Upgrading Homebrew packages..."
  /opt/homebrew/bin/brew upgrade
fi

# Clean up legacy treesitter parsers if present
if [[ -d "${HOME}/.local/share/nvim/lazy/nvim-treesitter/parser" ]]; then
  rm -rf "${HOME}/.local/share/nvim/lazy/nvim-treesitter/parser"
fi

# Sync and compile Neovim plugins and treesitter parsers headlessly
if command -v nvim >/dev/null 2>&1; then
  echo "==> Syncing Neovim plugins and treesitter..."
  nvim --headless "+Lazy! sync" "+qa" >/dev/null 2>&1 || true
fi

echo "==> System successfully updated!"
