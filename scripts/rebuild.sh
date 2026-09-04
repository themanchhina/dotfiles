#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
flake="path:${repo_dir}#chhina"

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

echo "==> Checking flake configuration..."
"${nix_bin}" flake check "path:${repo_dir}" --no-build

# Build safe PATH for sudo activation
safe_path="${PATH}:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin:/opt/homebrew/bin"

if [[ -x /run/current-system/sw/bin/darwin-rebuild ]]; then
  echo "==> Applying configuration via installed darwin-rebuild..."
  exec sudo env "PATH=${safe_path}" /run/current-system/sw/bin/darwin-rebuild switch --flake "${flake}"
fi

echo "==> Applying configuration via locked nix-darwin runner..."
exec sudo env "PATH=${safe_path}" "${nix_bin}" run \
  "path:${repo_dir}#darwinConfigurations.chhina.config.system.build.darwin-rebuild" \
  -- switch --flake "${flake}"
