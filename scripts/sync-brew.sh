#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "${repo_dir}/scripts/lib/utils.sh"

# The profile decides which packages are declared, so auditing without it reports
# the gated ones as drift on a home machine.
profile="${DOTFILES_PROFILE:-}"
while [[ $# -gt 0 ]]; do
  case "$1" in
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
Usage: sync-brew.sh [options]

Reports drift between installed Homebrew packages and darwin.nix. Read-only.

Options:
  --profile NAME   work (default) or home; must match how you rebuild
  -h, --help       Show this help message
EOF
      exit 0
      ;;
    *)
      echo "Error: unknown option '$1'. See --help." >&2
      exit 1
      ;;
  esac
done
validate_profile "${profile}" || exit 1
export DOTFILES_PROFILE="${profile}"

if ! command -v brew >/dev/null 2>&1 && [[ ! -x /opt/homebrew/bin/brew ]]; then
  echo "Error: Homebrew is not installed." >&2
  exit 1
fi

command -v jq >/dev/null 2>&1 || { echo "Error: jq is not installed." >&2; exit 1; }

brew_bin="$(command -v brew || echo "/opt/homebrew/bin/brew")"

echo "==> Auditing Homebrew packages against darwin.nix (profile: ${profile:-work})..."

source_nix_env
nix_bin="$(find_nix_bin "${repo_dir}")"

# Get installed top-level formulae, all formulae, casks, and taps.
# `leaves` prints full names and `list` short ones, so strip the tap from both.
installed_leaves="$("${brew_bin}" leaves 2>/dev/null | sed 's|.*/||' | sort || true)"
all_installed_brews="$("${brew_bin}" list --formula 2>/dev/null | sort || true)"
installed_casks="$("${brew_bin}" list --cask 2>/dev/null | sort || true)"
# homebrew/* are Homebrew's own and are never declared, so they are not drift.
installed_taps="$("${brew_bin}" tap 2>/dev/null | grep -v '^homebrew/' | sort || true)"

# Parse declared brews, casks, and taps via Nix evaluation (accurate, comments/formatting agnostic)
# sub() strips the tap prefix: `brew list` reports short names only.
declared_brews="$("${nix_bin}" eval --impure --json "path:${repo_dir}#darwinConfigurations.default.config.homebrew.brews" | jq -r '.[].name | sub(".*/"; "")' | sort)"
declared_casks="$("${nix_bin}" eval --impure --json "path:${repo_dir}#darwinConfigurations.default.config.homebrew.casks" | jq -r '.[].name' | sort)"
declared_taps="$("${nix_bin}" eval --impure --json "path:${repo_dir}#darwinConfigurations.default.config.homebrew.taps" | jq -r '.[].name' | sort)"
declared_mas="$("${nix_bin}" eval --impure --json "path:${repo_dir}#darwinConfigurations.default.config.homebrew.masApps" | jq -r '.[]' | sort)"

# Find top-level items installed on this Mac but missing in darwin.nix
missing_in_nix_brews="$(comm -23 <(echo "${installed_leaves}") <(echo "${declared_brews}") | grep -v '^$' || true)"
missing_in_nix_casks="$(comm -23 <(echo "${installed_casks}") <(echo "${declared_casks}") | grep -v '^$' || true)"
missing_in_nix_taps="$(comm -23 <(echo "${installed_taps}") <(echo "${declared_taps}") | grep -v '^$' || true)"

# Find items declared in darwin.nix but not installed (comparing against all installed formulas to avoid false positives on dependencies)
not_installed_brews="$(comm -13 <(echo "${all_installed_brews}") <(echo "${declared_brews}") | grep -v '^$' || true)"
not_installed_casks="$(comm -13 <(echo "${installed_casks}") <(echo "${declared_casks}") | grep -v '^$' || true)"
not_installed_taps="$(comm -13 <(echo "${installed_taps}") <(echo "${declared_taps}") | grep -v '^$' || true)"

if command -v mas >/dev/null 2>&1; then
  installed_mas="$(mas list 2>/dev/null | awk '{print $1}' | sort)"
  missing_in_nix_mas="$(comm -23 <(echo "${installed_mas}") <(echo "${declared_mas}") | grep -v '^$' || true)"
  not_installed_mas="$(comm -13 <(echo "${installed_mas}") <(echo "${declared_mas}") | grep -v '^$' || true)"
else
  echo "ℹ️  Skipping Mac App Store audit: mas is not installed."
  missing_in_nix_mas=""
  not_installed_mas=""
fi

has_diff=0

if [[ -n "${missing_in_nix_brews}" ]]; then
  has_diff=1
  echo ""
  echo "⚠️  Installed Formulae NOT yet in darwin.nix:"
  while IFS= read -r item; do
    echo "    \"${item}\""
  done <<< "${missing_in_nix_brews}"
fi

if [[ -n "${missing_in_nix_casks}" ]]; then
  has_diff=1
  echo ""
  echo "⚠️  Installed Casks NOT yet in darwin.nix:"
  while IFS= read -r item; do
    echo "    \"${item}\""
  done <<< "${missing_in_nix_casks}"
fi

if [[ -n "${missing_in_nix_taps}" ]]; then
  has_diff=1
  echo ""
  echo "⚠️  Tapped repositories NOT yet in darwin.nix:"
  while IFS= read -r item; do
    echo "    \"${item}\""
  done <<< "${missing_in_nix_taps}"
fi

if [[ -n "${missing_in_nix_mas}" ]]; then
  has_diff=1
  echo ""
  echo "⚠️  Mac App Store apps NOT yet in darwin.nix:"
  while IFS= read -r item; do
    echo "    ${item}"
  done <<< "${missing_in_nix_mas}"
fi

if [[ -n "${not_installed_brews}" ]]; then
  has_diff=1
  echo ""
  echo "ℹ️  Formulae declared in darwin.nix but not currently installed:"
  while IFS= read -r item; do
    echo "    ${item}"
  done <<< "${not_installed_brews}"
fi

if [[ -n "${not_installed_casks}" ]]; then
  has_diff=1
  echo ""
  echo "ℹ️  Casks declared in darwin.nix but not currently installed:"
  while IFS= read -r item; do
    echo "    ${item}"
  done <<< "${not_installed_casks}"
fi

if [[ -n "${not_installed_taps}" ]]; then
  has_diff=1
  echo ""
  echo "ℹ️  Taps declared in darwin.nix but not currently tapped:"
  while IFS= read -r item; do
    echo "    ${item}"
  done <<< "${not_installed_taps}"
fi

if [[ -n "${not_installed_mas}" ]]; then
  has_diff=1
  echo ""
  echo "ℹ️  Mac App Store apps declared in darwin.nix but not currently installed:"
  while IFS= read -r item; do
    echo "    ${item}"
  done <<< "${not_installed_mas}"
fi

if [[ "${has_diff}" -eq 0 ]]; then
  echo "✅ darwin.nix is in sync with all installed Homebrew packages!"
else
  echo ""
  echo "To keep your configuration reproducible on new machines, add unmanaged packages to darwin.nix"
  echo "and run ./scripts/rebuild.sh"
fi
