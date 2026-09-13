#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "${repo_dir}/scripts/lib/utils.sh"

clean=0
profile=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean|-c)
      clean=1
      shift
      ;;
    --profile)
      [[ $# -ge 2 ]] || { echo "Error: --profile requires a value." >&2; exit 1; }
      profile="$2"
      shift 2
      ;;
    --profile=*)
      profile="${1#*=}"
      shift
      ;;
    -h|--help)
      cat << 'EOF'
Usage: rebuild.sh [options]

Options:
  --clean, -c      Purge Neovim plugin cache and reinstall fresh from lockfile
  --profile NAME   work (default) or home. "home" adds personal VPN, sync and
                   network tooling. Set manualProfile in flake.nix to make it
                   permanent for this machine.
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

validate_profile "${profile}" || exit 1

resolve_system_identity
# Unconditional: home.nix exports DOTFILES_DIR into every shell, so honouring an
# inherited value would link another checkout's config into this build.
export DOTFILES_DIR="${repo_dir}"
export DOTFILES_PROFILE="${profile:-${DOTFILES_PROFILE:-}}"
# An inherited value reaches root's Nix eval too, so validate after resolution.
validate_profile "${DOTFILES_PROFILE}" || exit 1

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
    "DOTFILES_PROFILE=${DOTFILES_PROFILE}" \
    /run/current-system/sw/bin/darwin-rebuild switch --impure --flake "${flake}"
else
  echo "==> Applying configuration via locked nix-darwin runner..."
  sudo env \
    "PATH=${safe_path}" \
    "USER=${USER}" \
    "DARWIN_USER=${DARWIN_USER}" \
    "DOTFILES_DIR=${DOTFILES_DIR}" \
    "DOTFILES_PROFILE=${DOTFILES_PROFILE}" \
    "${nix_bin}" run --impure \
    "path:${repo_dir}#darwinConfigurations.default.config.system.build.darwin-rebuild" \
    -- switch --impure --flake "${flake}"
fi

# update.sh runs its own sync pass, so restoring to the lockfile first would
# clone every plugin only to update it immediately.
[[ "${_DOTFILES_SKIP_NVIM:-0}" == "1" ]] || restore_nvim_plugins "${clean}"

echo "==> Rebuild completed successfully!"
