#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
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

# Resolve target user, host, and dotfiles directory from args, environment, or system
target_user="${DARWIN_USER:-${SUDO_USER:-${USER:-$(id -un)}}}"
if [[ "${target_user}" == "root" ]]; then
  echo "Error: Cannot rebuild as root. Run without sudo (sudo will be prompted automatically)." >&2
  exit 1
fi
target_host="${target_host:-${DARWIN_HOST:-${HOSTNAME:-${HOST:-$(scutil --get LocalHostName 2>/dev/null || hostname -s)}}}}"
export USER="${target_user}"
export HOSTNAME="${target_host}"
export HOST="${target_host}"
export DARWIN_USER="${target_user}"
export DARWIN_HOST="${target_host}"
export DOTFILES_DIR="${DOTFILES_DIR:-${repo_dir}}"

flake="path:${repo_dir}#default"

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

# Nix flakes in a Git repo only see files tracked by Git.
# Automatically stage any new/untracked files with intent-to-add (-N) so Nix can evaluate them.
if git -C "${repo_dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  untracked="$(git -C "${repo_dir}" ls-files --others --exclude-standard)"
  if [[ -n "${untracked}" ]]; then
    echo "==> Staging untracked files with intent-to-add (git add -N) for Nix..."
    git -C "${repo_dir}" add -N .
  fi
fi

echo "==> Checking flake configuration for user '${target_user}' on host '${target_host}'..."
"${nix_bin}" flake check --impure "path:${repo_dir}" --no-build

# Build safe PATH for sudo activation
safe_path="${PATH}:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/opt/homebrew/bin"

if [[ -x /run/current-system/sw/bin/darwin-rebuild ]]; then
  echo "==> Applying configuration via installed darwin-rebuild..."
  sudo env \
    "PATH=${safe_path}" \
    "USER=${target_user}" \
    "HOSTNAME=${target_host}" \
    "HOST=${target_host}" \
    "DARWIN_USER=${target_user}" \
    "DARWIN_HOST=${target_host}" \
    "DOTFILES_DIR=${DOTFILES_DIR}" \
    /run/current-system/sw/bin/darwin-rebuild switch --impure --flake "${flake}"
else
  echo "==> Applying configuration via locked nix-darwin runner..."
  sudo env \
    "PATH=${safe_path}" \
    "USER=${target_user}" \
    "HOSTNAME=${target_host}" \
    "HOST=${target_host}" \
    "DARWIN_USER=${target_user}" \
    "DARWIN_HOST=${target_host}" \
    "DOTFILES_DIR=${DOTFILES_DIR}" \
    "${nix_bin}" run --impure \
    "path:${repo_dir}#darwinConfigurations.default.config.system.build.darwin-rebuild" \
    -- switch --impure --flake "${flake}"
fi

# Clean up stale legacy treesitter files and restore lockfile commits headlessly
if command -v nvim >/dev/null 2>&1; then
  if [[ ${clean} -eq 1 ]]; then
    echo "==> Purging Neovim plugin caches (~/.local/share/nvim/lazy, site, cache, state)..."
    rm -rf "${HOME}/.local/share/nvim/lazy" "${HOME}/.local/share/nvim/site" "${HOME}/.cache/nvim" "${HOME}/.local/state/nvim"
  fi
  rm -f "${HOME}/.local/share/nvim/lazy/nvim-treesitter/lua/nvim-treesitter.lua"
  if [[ -d "${HOME}/.local/share/nvim/lazy/nvim-treesitter/parser" ]]; then
    rm -rf "${HOME}/.local/share/nvim/lazy/nvim-treesitter/parser"
  fi
  echo "==> Restoring Neovim plugins and treesitter parsers..."
  nvim --headless "+Lazy! restore" "+qa" >/dev/null 2>&1 || true
fi

echo "==> Rebuild completed successfully!"

