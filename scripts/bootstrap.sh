#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "${repo_dir}/scripts/lib/utils.sh"

usage_text=$(cat << 'EOF'
Usage: bootstrap.sh [options]

First activation on a new Mac: installs Determinate Nix if absent, then applies
the configuration via rebuild.sh.

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

echo "==> Validating system requirements..."

# hw.optional.arm64, not uname -m, which reports x86_64 under Rosetta translation.
if [[ "$(uname -s)" != "Darwin" || "$(sysctl -n hw.optional.arm64 2>/dev/null)" != "1" ]]; then
  echo "Error: This configuration currently supports Apple Silicon macOS only." >&2
  exit 1
fi

resolve_system_identity
echo "==> Bootstrapping for user '${USER}'..."

# Ensure Xcode Command Line Tools are installed (required for Homebrew and native builds)
if ! xcode-select -p >/dev/null 2>&1; then
  echo "==> Xcode Command Line Tools not detected. Prompting installation..."
  trap 'rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress' EXIT INT TERM
  touch /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  xcode-select --install 2>/dev/null || true
  echo "Waiting for Xcode Command Line Tools to complete installation (30 min max)..."
  # Bounded: the install dialog is a GUI whose Cancel is indistinguishable from slow.
  for _ in $(seq 360); do
    xcode-select -p >/dev/null 2>&1 && break
    sleep 5
  done
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "Error: Xcode Command Line Tools still missing. Install them, then re-run." >&2
    exit 1
  fi
  rm -f /tmp/.com.apple.dt.CommandLineTools.installondemand.in-progress
  trap - EXIT INT TERM
  echo "==> Xcode Command Line Tools installed."
fi

# Pre-flight migration checks for machines upgrading from older versions
echo "==> Running pre-flight migration checks..."

# Back up ~/.config/nvim if it is an existing directory (prevent Home Manager collision)
if [[ -d "${HOME}/.config/nvim" && ! -L "${HOME}/.config/nvim" ]]; then
  backup_dir="${HOME}/.config/nvim.before-nix-$(date +%Y%m%d%H%M%S)"
  echo "==> Backing up existing ~/.config/nvim directory to ${backup_dir}..."
  mv "${HOME}/.config/nvim" "${backup_dir}"
fi

# Ensure strict SSH directory and file permissions
mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh"
if [[ -f "${repo_dir}/config/ssh/config" ]]; then
  chmod 600 "${repo_dir}/config/ssh/config"
fi

if ! command -v nix >/dev/null 2>&1 && [[ ! -x /nix/var/nix/profiles/default/bin/nix ]]; then
  if [[ ! -t 0 ]]; then
    echo "Error: Determinate Nix is not installed and stdin is not a terminal." >&2
    echo "Install it first: https://install.determinate.systems/nix" >&2
    exit 1
  fi
  echo ""
  read -r -p "Determinate Nix is not installed. Install it now? [y/N] " answer || answer=""
  if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
    echo "Install Determinate Nix, then run this script again." >&2
    exit 1
  fi

  echo "==> Installing Determinate Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install
fi

source_nix_env

echo "==> Applying system configuration via rebuild script..."
"${repo_dir}/scripts/rebuild.sh" "$@"

echo "==> Bootstrap completed successfully!"
