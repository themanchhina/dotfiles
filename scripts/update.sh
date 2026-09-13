#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "${repo_dir}/scripts/lib/utils.sh"

usage_text=$(cat << 'EOF'
Usage: update.sh [options]

Updates Nix flake inputs and Homebrew packages, then applies the configuration.

Options:
  --clean, -c      Purge Neovim plugin cache and reinstall fresh from lockfile
  --profile NAME   work (default) or home
  -h, --help       Show this help message
EOF
)

# Validate first: everything below mutates before rebuild.sh sees these args.
rc=0
validate_passthrough_args "${usage_text}" "$@" || rc=$?
case ${rc} in
  0) ;;
  2) exit 0 ;;
  *) exit 1 ;;
esac

clean=0
for a in "$@"; do [[ "$a" == "--clean" || "$a" == "-c" ]] && clean=1; done

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
_DOTFILES_SKIP_NVIM=1 "${repo_dir}/scripts/rebuild.sh" "$@"

if [[ -x "${brew_bin}" ]]; then
  echo "==> Upgrading Homebrew packages..."
  "${brew_bin}" upgrade
fi

sync_nvim_plugins "${clean}"

echo "==> System successfully updated!"
