#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

echo "==> Validating system requirements..."

if [[ "$(uname -s)" != "Darwin" || "$(uname -m)" != "arm64" ]]; then
  echo "Error: This configuration currently supports Apple Silicon macOS only." >&2
  exit 1
fi

if [[ "$(id -un)" != "chhina" ]]; then
  echo "Error: This configuration expects the macOS account name 'chhina'." >&2
  exit 1
fi

# Ensure Xcode Command Line Tools are installed (required for Homebrew and native builds)
if ! xcode-select -p >/dev/null 2>&1; then
  echo "==> Xcode Command Line Tools not detected. Prompting installation..."
  xcode-select --install || true
  echo ""
  echo "Please complete the Apple Xcode Command Line Tools installation dialog,"
  echo "then rerun this bootstrap script: ./scripts/bootstrap.sh"
  exit 1
fi

# Check for Nix and install via Determinate Systems if absent
if ! command -v nix >/dev/null 2>&1 && [[ ! -x /nix/var/nix/profiles/default/bin/nix ]]; then
  echo ""
  read -r -p "Determinate Nix is not installed. Install it now? [y/N] " answer
  if [[ ! "${answer}" =~ ^[Yy]$ ]]; then
    echo "Install Determinate Nix, then run this script again." >&2
    exit 1
  fi

  echo "==> Installing Determinate Nix..."
  curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix \
    | sh -s -- install
fi

# Ensure Nix environment is active in the current process
if [[ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]]; then
  # shellcheck disable=SC1091
  . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi

if [[ -d /nix/var/nix/profiles/default/bin ]]; then
  export PATH="/nix/var/nix/profiles/default/bin:${PATH}"
fi

echo "==> Handing off to rebuild script..."
exec "${repo_dir}/scripts/rebuild.sh"
