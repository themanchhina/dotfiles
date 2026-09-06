#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "${repo_dir}/scripts/lib/utils.sh"

source_nix_env
nix_bin="$(find_nix_bin "${repo_dir}")"

stage_untracked_for_nix "${repo_dir}"

if [[ -x /opt/homebrew/bin/brew ]]; then
  echo "==> Updating Homebrew formula and cask indexes..."
  /opt/homebrew/bin/brew update
fi

echo "==> Updating Nix flake inputs..."
"${nix_bin}" flake update --flake "path:${repo_dir}"

echo "==> Rebuilding system..."
"${repo_dir}/scripts/rebuild.sh" "$@"

if [[ -x /opt/homebrew/bin/brew ]]; then
  echo "==> Upgrading Homebrew packages..."
  /opt/homebrew/bin/brew upgrade
fi

sync_nvim_plugins

echo "==> System successfully updated!"
