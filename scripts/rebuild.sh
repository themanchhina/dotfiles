#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "${repo_dir}/scripts/lib/utils.sh"

clean=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean|-c)
      clean=1
      shift
      ;;
    -h|--help)
      cat << 'EOF'
Usage: rebuild.sh [options]

Options:
  --clean, -c      Purge Neovim plugin cache and reinstall fresh from lockfile
  -h, --help       Show this help message
EOF
      exit 0
      ;;
    *)
      echo "Error: unexpected argument '$1'. See --help." >&2
      exit 1
      ;;
  esac
done

resolve_system_identity
export DOTFILES_DIR="${DOTFILES_DIR:-${repo_dir}}"

flake="path:${repo_dir}#default"

source_nix_env
nix_bin="$(find_nix_bin "${repo_dir}")"

# flake check skips darwinConfigurations; only an eval catches module errors.
echo "==> Checking flake configuration for user '${USER}'..."
"${nix_bin}" eval --impure --raw \
  "path:${repo_dir}#darwinConfigurations.default.config.system.build.toplevel.drvPath" \
  >/dev/null

# Fixed, not inherited: activation runs as root and ~/.local/bin is user-writable.
safe_path="/run/current-system/sw/bin:/nix/var/nix/profiles/default/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin"

if [[ -x /run/current-system/sw/bin/darwin-rebuild ]]; then
  echo "==> Applying configuration via installed darwin-rebuild..."
  sudo env \
    "PATH=${safe_path}" \
    "USER=${USER}" \
    "DARWIN_USER=${DARWIN_USER}" \
    "DOTFILES_DIR=${DOTFILES_DIR}" \
    /run/current-system/sw/bin/darwin-rebuild switch --impure --flake "${flake}"
else
  echo "==> Applying configuration via locked nix-darwin runner..."
  sudo env \
    "PATH=${safe_path}" \
    "USER=${USER}" \
    "DARWIN_USER=${DARWIN_USER}" \
    "DOTFILES_DIR=${DOTFILES_DIR}" \
    "${nix_bin}" run --impure \
    "path:${repo_dir}#darwinConfigurations.default.config.system.build.darwin-rebuild" \
    -- switch --impure --flake "${flake}"
fi

restore_nvim_plugins "${clean}"

echo "==> Rebuild completed successfully!"
