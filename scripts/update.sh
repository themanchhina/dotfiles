#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "${repo_dir}/scripts/lib/utils.sh"

source_nix_env
nix_bin="$(find_nix_bin "${repo_dir}")"
brew_bin="$(command -v brew || echo "/opt/homebrew/bin/brew")"

if [[ -x "${brew_bin}" ]]; then
  echo "==> Updating Homebrew formula and cask indexes..."
  "${brew_bin}" update
fi

echo "==> Updating Nix flake inputs..."
"${nix_bin}" flake update --flake "path:${repo_dir}"

echo "==> Rebuilding system..."
"${repo_dir}/scripts/rebuild.sh" "$@"

if [[ -x "${brew_bin}" ]]; then
  echo "==> Upgrading Homebrew packages..."
  "${brew_bin}" upgrade
fi

sync_nvim_plugins

echo "==> System successfully updated!"
