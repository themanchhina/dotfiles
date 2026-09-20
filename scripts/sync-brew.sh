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

brew_bin="$(find_brew_bin)"
[[ -n "${brew_bin}" ]] || { echo "Error: Homebrew is not installed." >&2; exit 1; }

command -v jq >/dev/null 2>&1 || { echo "Error: jq is not installed." >&2; exit 1; }

echo "==> Auditing Homebrew packages against darwin.nix (profile: ${profile:-work})..."

source_nix_env
nix_bin="$(find_nix_bin "${repo_dir}")"

# Explicitly installed formulae may also be dependencies, so `leaves` misses them.
installed_json="$("${brew_bin}" info --json=v2 --installed)"
requested_brews="$(jq -r '.formulae[] | select(any(.installed[]; .installed_on_request == true)) | .full_name' <<< "${installed_json}" | sort)"
all_installed_brews="$(jq -r '.formulae[].full_name' <<< "${installed_json}" | sort)"
installed_casks="$(jq -r '.casks[].full_token' <<< "${installed_json}" | sort)"
# homebrew/* are Homebrew's own and are never declared, so they are not drift.
installed_taps="$("${brew_bin}" tap | sed '/^homebrew\//d' | sort)"

# One eval, projected to just the names: each `nix eval` is a full module-system
# evaluation, and --impure gets no eval cache.
declared_json="$("${nix_bin}" eval --impure --json \
  "path:${repo_dir}#darwinConfigurations.default.config.homebrew" \
  --apply 'h: { brews = map (b: b.name) h.brews; casks = map (c: c.name) h.casks; taps = map (t: t.name) h.taps; masApps = builtins.attrValues h.masApps; masAppMap = h.masApps; }')"

# Full names retain tap identity on both sides of the comparison.
declared_brews="$(jq -r '.brews[]' <<< "${declared_json}" | sort)"
declared_casks="$(jq -r '.casks[]' <<< "${declared_json}" | sort)"
declared_taps="$(jq -r '.taps[]' <<< "${declared_json}" | sort)"
declared_mas="$(jq -r '.masApps[]' <<< "${declared_json}" | sort)"

# Find top-level items installed on this Mac but missing in darwin.nix
missing_in_nix_brews="$(comm -23 <(echo "${requested_brews}") <(echo "${declared_brews}") | grep -v '^$' || true)"
missing_in_nix_casks="$(comm -23 <(echo "${installed_casks}") <(echo "${declared_casks}") | grep -v '^$' || true)"
missing_in_nix_taps="$(comm -23 <(echo "${installed_taps}") <(echo "${declared_taps}") | grep -v '^$' || true)"

# Find items declared in darwin.nix but not installed (comparing against all installed formulas to avoid false positives on dependencies)
not_installed_brews="$(comm -13 <(echo "${all_installed_brews}") <(echo "${declared_brews}") | grep -v '^$' || true)"
not_installed_casks="$(comm -13 <(echo "${installed_casks}") <(echo "${declared_casks}") | grep -v '^$' || true)"
not_installed_taps="$(comm -13 <(echo "${installed_taps}") <(echo "${declared_taps}") | grep -v '^$' || true)"

if command -v mas >/dev/null 2>&1; then
  mas_raw="$(mas list 2>/dev/null || true)"
  installed_mas="$(echo "${mas_raw}" | awk '{print $1}' | grep -v '^$' | sort)"
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
    app_name="$(echo "${mas_raw}" | awk -v id="${item}" '$1 == id { sub(/^[[:space:]]*[0-9]+[[:space:]]+/, ""); sub(/[[:space:]]+\([^)]+\)[[:space:]]*$/, ""); print; exit }')"
    if [[ -n "${app_name}" ]]; then
      echo "    \"${app_name}\" = ${item};"
    else
      echo "    ${item}"
    fi
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
    app_name="$(jq -r --arg id "${item}" '.masAppMap // {} | to_entries[] | select(.value == ($id|tonumber)) | .key' <<< "${declared_json}" 2>/dev/null || true)"
    if [[ -n "${app_name}" ]]; then
      echo "    \"${app_name}\" = ${item};"
    else
      echo "    ${item}"
    fi
  done <<< "${not_installed_mas}"
fi

if [[ "${has_diff}" -eq 0 ]]; then
  echo "✅ darwin.nix is in sync with all installed Homebrew packages!"
else
  echo ""
  echo "To keep your configuration reproducible on new machines, add unmanaged packages to darwin.nix"
  echo "and run ./scripts/rebuild.sh"
fi
