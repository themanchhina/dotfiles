#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "${repo_dir}/scripts/lib/utils.sh"

clean=0
target_host=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean|-c)
      clean=1
      shift
      ;;
    -h|--help)
      cat << 'EOF'
Usage: rebuild.sh [host] [options]

Options:
  --clean, -c      Purge Neovim plugin cache and reinstall fresh from lockfile
  -h, --help       Show this help message
EOF
      exit 0
      ;;
    *)
      if [[ -z "${target_host}" ]]; then
        target_host="$1"
      fi
      shift
      ;;
  esac
done

resolve_system_identity "" "${target_host}"
export DOTFILES_DIR="${DOTFILES_DIR:-${repo_dir}}"

flake="path:${repo_dir}#default"

source_nix_env
nix_bin="$(find_nix_bin "${repo_dir}")"

stage_untracked_for_nix "${repo_dir}"

echo "==> Checking flake configuration for user '${USER}' on host '${HOSTNAME}'..."
"${nix_bin}" flake check --impure "path:${repo_dir}" --no-build

# Build safe PATH for sudo activation
safe_path="${PATH}:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/opt/homebrew/bin"

if [[ -x /run/current-system/sw/bin/darwin-rebuild ]]; then
  echo "==> Applying configuration via installed darwin-rebuild..."
  sudo env \
    "PATH=${safe_path}" \
    "USER=${USER}" \
    "HOSTNAME=${HOSTNAME}" \
    "HOST=${HOST}" \
    "DARWIN_USER=${DARWIN_USER}" \
    "DARWIN_HOST=${DARWIN_HOST}" \
    "DOTFILES_DIR=${DOTFILES_DIR}" \
    /run/current-system/sw/bin/darwin-rebuild switch --impure --flake "${flake}"
else
  echo "==> Applying configuration via locked nix-darwin runner..."
  sudo env \
    "PATH=${safe_path}" \
    "USER=${USER}" \
    "HOSTNAME=${HOSTNAME}" \
    "HOST=${HOST}" \
    "DARWIN_USER=${DARWIN_USER}" \
    "DARWIN_HOST=${DARWIN_HOST}" \
    "DOTFILES_DIR=${DOTFILES_DIR}" \
    "${nix_bin}" run --impure \
    "path:${repo_dir}#darwinConfigurations.default.config.system.build.darwin-rebuild" \
    -- switch --impure --flake "${flake}"
fi

restore_nvim_plugins "${clean}"

echo "==> Rebuild completed successfully!"
