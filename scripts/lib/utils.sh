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

# Locate brew; empty output means Homebrew is absent.
find_brew_bin() {
  if command -v brew >/dev/null 2>&1; then
    command -v brew
  elif [[ -x /opt/homebrew/bin/brew ]]; then
    echo "/opt/homebrew/bin/brew"
  fi
}

# work|home only; empty means "fall back to the default".
validate_profile() {
  case "${1:-}" in
    work|home|"") return 0 ;;
    *)
      echo "Error: profile must be 'work' or 'home', got '${1}'." >&2
      return 1
      ;;
  esac
}

# bootstrap, rebuild and update take the same options; $1 describes this script.
print_usage() {
  printf 'Usage: %s [options]\n\n%s\n\nOptions:\n' "$(basename "$0")" "$1"
  cat << 'EOF'
  --clean, -c      Purge Neovim plugin cache and reinstall fresh from lockfile
  --profile NAME   work (default) or home. "home" adds personal VPN, sync and
                   network tooling. Set manualProfile in flake.nix to make it
                   permanent for this machine.
  -h, --help       Show this help message
EOF
}

# Reject unknown options before the caller mutates anything. $1 is the summary.
# Returns 0 ok, 1 reject, 2 help shown.
validate_passthrough_args() {
  local summary="$1"
  shift
  local args=("$@") i=0
  local profile=""
  while [[ ${i} -lt ${#args[@]} ]]; do
    case "${args[${i}]}" in
      --clean|-c) ;;
      --profile)
        i=$((i + 1))
        [[ ${i} -lt ${#args[@]} ]] || { echo "Error: --profile requires a value." >&2; return 1; }
        validate_profile "${args[${i}]}" || return 1
        profile="${args[${i}]}"
        ;;
      --profile=*)
        validate_profile "${args[${i}]#*=}" || return 1
        profile="${args[${i}]#*=}"
        ;;
      -h|--help)
        print_usage "${summary}"
        return 2
        ;;
      *)
        echo "Error: unknown option '${args[${i}]}'. See --help." >&2
        return 1
        ;;
    esac
    i=$((i + 1))
  done
  # Match rebuild's fallback before bootstrap/update perform any mutations.
  validate_profile "${profile:-${DOTFILES_PROFILE:-}}"
}

# Resolve the target user, exporting validated environment variables
resolve_system_identity() {
  local resolved_user="${1:-${DARWIN_USER:-${SUDO_USER:-${USER:-$(id -un)}}}}"
  if [[ "${resolved_user}" == "root" ]]; then
    echo "Error: Cannot run configuration as root. Run without sudo (sudo will be prompted automatically)." >&2
    return 1
  fi

  export USER="${resolved_user}"
  export DARWIN_USER="${resolved_user}"
}

# Retain diagnostics and fail the overall command when editor setup is incomplete.
run_nvim_headless() {
  local label="$1"
  local cmd="$2"
  local log
  log="$(mktemp "${TMPDIR:-/tmp}/dotfiles-nvim.XXXXXX")" || return 1

  echo "==> ${label}"
  # config.sync quits on success; reaching the fallback means it failed to load.
  if ! nvim --headless "${cmd}" "+cquit 1" </dev/null >"${log}" 2>&1; then
    echo "Error: Neovim plugin setup failed. Log: ${log}" >&2
    return 1
  fi
  rm -f "${log}"
}

# Check before the purge: without nvim, deleting the tree just loses it.
nvim_pass() {
  local clean_mode="$1" label="$2" cmd="$3"

  # A first activation does not refresh the calling shell's PATH.
  if ! command -v nvim >/dev/null 2>&1; then
    export PATH="${PATH}:/etc/profiles/per-user/${DARWIN_USER:-${USER}}/bin"
  fi
  if ! command -v nvim >/dev/null 2>&1; then
    echo "Error: Neovim is unavailable; editor setup was not completed." >&2
    return 1
  fi

  if [[ "${clean_mode}" -eq 1 ]]; then
    # Not ~/.local/state/nvim: that is shada and undo, which cannot be rebuilt.
    echo "==> Purging Neovim plugin caches (~/.local/share/nvim/lazy, site, ~/.cache/nvim)..."
    rm -rf "${HOME}/.local/share/nvim/lazy" "${HOME}/.local/share/nvim/site" "${HOME}/.cache/nvim"
  fi

  run_nvim_headless "${label}" "${cmd}"
}

# Pin plugins to lazy-lock.json
restore_nvim_plugins() {
  nvim_pass "${1:-0}" "Restoring Neovim plugins and treesitter parsers..." "+lua require('config.sync')('restore')"
}

# Advance plugins and rewrite lazy-lock.json
sync_nvim_plugins() {
  nvim_pass "${1:-0}" "Syncing Neovim plugins and treesitter..." "+lua require('config.sync')('sync')"
}
