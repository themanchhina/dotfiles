#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "${repo_dir}/scripts/lib/utils.sh"

# Validate before mutating anything: these are forwarded to rebuild.sh, and by
# the time it rejects an option brew and flake.lock have already moved. --help
# must exit here too, or rebuild.sh prints help and skips the switch while this
# script still upgrades everything and reports success.
args=("$@")
i=0
while [[ ${i} -lt ${#args[@]} ]]; do
  case "${args[${i}]}" in
    --clean|-c) ;;
    --profile)
      i=$((i + 1))   # consume the value token too
      ;;
    --profile=*) ;;
    -h|--help)
      cat << 'EOF'
Usage: update.sh [options]

Updates Nix flake inputs and Homebrew packages, then applies the configuration.

Options:
  --clean, -c      Purge Neovim plugin cache and reinstall fresh from lockfile
  --profile NAME   work (default) or home
  -h, --help       Show this help message
EOF
      exit 0
      ;;
    *)
      echo "Error: unknown option '${args[${i}]}'. See --help." >&2
      exit 1
      ;;
  esac
  i=$((i + 1))
done

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
