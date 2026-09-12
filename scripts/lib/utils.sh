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

# Warns but never fails: a plugin problem must not abort a good system switch.
run_nvim_headless() {
  local label="$1"
  local cmd="$2"
  local log="${TMPDIR:-/tmp}/dotfiles-nvim.log"

  if ! command -v nvim >/dev/null 2>&1; then
    return 0
  fi

  echo "==> ${label}"
  if ! nvim --headless "${cmd}" "+qa" >"${log}" 2>&1; then
    echo "    Warning: nvim ${cmd} exited non-zero. Log: ${log}" >&2
  fi
}

# Restore Neovim plugins from lazy-lock.json headlessly
restore_nvim_plugins() {
  local clean_mode="${1:-0}"

  if [[ "${clean_mode}" -eq 1 ]]; then
    # Not ~/.local/state/nvim: that is shada and undo, which restore cannot rebuild.
    echo "==> Purging Neovim plugin caches (~/.local/share/nvim/lazy, site, ~/.cache/nvim)..."
    rm -rf "${HOME}/.local/share/nvim/lazy" "${HOME}/.local/share/nvim/site" "${HOME}/.cache/nvim"
  fi

  run_nvim_headless "Restoring Neovim plugins and treesitter parsers..." "+Lazy! restore"
}

# Sync and update Neovim plugins headlessly
sync_nvim_plugins() {
  run_nvim_headless "Syncing Neovim plugins and treesitter..." "+Lazy! sync"
}
