#!/usr/bin/env bash
# scripts/lib/utils.sh - Shared utility functions for dotfiles automation

# Source Nix environment profile if present
source_nix_env() {
  if [[ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]]; then
    # shellcheck disable=SC1091
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
  fi
  if [[ -d /nix/var/nix/profiles/default/bin ]]; then
    export PATH="/nix/var/nix/profiles/default/bin:${PATH}"
  fi
}

# Locate nix binary or report error
find_nix_bin() {
  local repo_dir="$1"
  if command -v nix >/dev/null 2>&1; then
    command -v nix
  elif [[ -x /nix/var/nix/profiles/default/bin/nix ]]; then
    echo "/nix/var/nix/profiles/default/bin/nix"
  else
    echo "Error: Nix is not installed. Run ${repo_dir}/scripts/bootstrap.sh first." >&2
    return 1
  fi
}

# Resolve system user and host, exporting validated environment variables
resolve_system_identity() {
  local user_arg="${1:-}"
  local host_arg="${2:-}"

  local resolved_user="${user_arg:-${DARWIN_USER:-${SUDO_USER:-${USER:-$(id -un)}}}}"
  if [[ "${resolved_user}" == "root" ]]; then
    echo "Error: Cannot run configuration as root. Run without sudo (sudo will be prompted automatically)." >&2
    return 1
  fi

  local resolved_host="${host_arg:-${DARWIN_HOST:-${HOSTNAME:-${HOST:-$(scutil --get LocalHostName 2>/dev/null || hostname -s)}}}}"

  export USER="${resolved_user}"
  export HOSTNAME="${resolved_host}"
  export HOST="${resolved_host}"
  export DARWIN_USER="${resolved_user}"
  export DARWIN_HOST="${resolved_host}"
}

# Nix flakes in a Git repo only see tracked files.
# Automatically stage untracked files with intent-to-add (-N).
stage_untracked_for_nix() {
  local dir="${1:-.}"
  if git -C "${dir}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    local untracked
    untracked="$(git -C "${dir}" ls-files --others --exclude-standard)"
    if [[ -n "${untracked}" ]]; then
      echo "==> Staging untracked files with intent-to-add (git add -N) for Nix..."
      git -C "${dir}" add -N .
    fi
  fi
}

# Restore Neovim plugins from lazy-lock.json headlessly
restore_nvim_plugins() {
  local clean_mode="${1:-0}"

  if ! command -v nvim >/dev/null 2>&1; then
    return 0
  fi

  if [[ "${clean_mode}" -eq 1 ]]; then
    echo "==> Purging Neovim plugin caches (~/.local/share/nvim/lazy, site, cache, state)..."
    rm -rf "${HOME}/.local/share/nvim/lazy" "${HOME}/.local/share/nvim/site" "${HOME}/.cache/nvim" "${HOME}/.local/state/nvim"
  fi

  echo "==> Restoring Neovim plugins and treesitter parsers..."
  nvim --headless "+Lazy! restore" "+qa" >/dev/null 2>&1 || true
}

# Sync and update Neovim plugins headlessly
sync_nvim_plugins() {
  if ! command -v nvim >/dev/null 2>&1; then
    return 0
  fi

  echo "==> Syncing Neovim plugins and treesitter..."
  nvim --headless "+Lazy! sync" "+qa" >/dev/null 2>&1 || true
}
