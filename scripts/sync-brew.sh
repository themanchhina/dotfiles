#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
darwin_file="${repo_dir}/darwin.nix"

if ! command -v brew >/dev/null 2>&1 && [[ ! -x /opt/homebrew/bin/brew ]]; then
  echo "Error: Homebrew is not installed." >&2
  exit 1
fi

brew_bin="$(command -v brew || echo "/opt/homebrew/bin/brew")"

echo "==> Auditing Homebrew packages against darwin.nix..."

# Get installed top-level formulae and casks
installed_brews="$("${brew_bin}" leaves 2>/dev/null | sort)"
installed_casks="$("${brew_bin}" list --cask 2>/dev/null | sort)"

# Parse declared brews and casks from darwin.nix
# Extract lines inside brews = [ ... ] and casks = [ ... ]
parse_section() {
  local section="$1"
  awk -v sec="${section}" '
    $0 ~ sec "[[:space:]]*=[[:space:]]*\\[" { in_sec=1; next }
    in_sec && /\];/ { in_sec=0 }
    in_sec && /"[^"]+"/ {
      match($0, /"[^"]+"/)
      val = substr($0, RSTART+1, RLENGTH-2)
      print val
    }
  ' "${darwin_file}" | sort
}

declared_brews="$(parse_section "brews")"
declared_casks="$(parse_section "casks")"

# Find items installed on this Mac but missing in darwin.nix
missing_in_nix_brews="$(comm -23 <(echo "${installed_brews}") <(echo "${declared_brews}") | grep -v '^$' || true)"
missing_in_nix_casks="$(comm -23 <(echo "${installed_casks}") <(echo "${declared_casks}") | grep -v '^$' || true)"

# Find items declared in darwin.nix but not installed
not_installed_brews="$(comm -13 <(echo "${installed_brews}") <(echo "${declared_brews}") | grep -v '^$' || true)"
not_installed_casks="$(comm -13 <(echo "${installed_casks}") <(echo "${declared_casks}") | grep -v '^$' || true)"

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

if [[ -n "${not_installed_brews}" ]]; then
  echo ""
  echo "ℹ️  Formulae declared in darwin.nix but not currently installed:"
  while IFS= read -r item; do
    echo "    ${item}"
  done <<< "${not_installed_brews}"
fi

if [[ -n "${not_installed_casks}" ]]; then
  echo ""
  echo "ℹ️  Casks declared in darwin.nix but not currently installed:"
  while IFS= read -r item; do
    echo "    ${item}"
  done <<< "${not_installed_casks}"
fi

if [[ "${has_diff}" -eq 0 ]]; then
  echo "✅ darwin.nix is in sync with all installed Homebrew packages!"
else
  echo ""
  echo "To keep your configuration reproducible on new machines, add unmanaged packages to darwin.nix"
  echo "and run ./scripts/rebuild.sh"
fi
