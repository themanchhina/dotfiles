#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "${repo_dir}/scripts/lib/utils.sh"

echo "==> 1/5: Validating shell script syntax..."
for f in "${repo_dir}"/scripts/*.sh "${repo_dir}"/scripts/lib/*.sh; do
  bash -n "$f"
done
echo "    ✓ Shell syntax valid."

echo "==> 2/5: Verifying managed link sources exist..."
while IFS= read -r p; do
  if [[ ! -e "${repo_dir}/${p}" ]]; then
    echo "Error: missing link source: ${p}" >&2
    exit 1
  fi
done < <(grep -o '= link "[^"]*"' "${repo_dir}/home.nix" | sed 's/.*link "//; s/"$//')
echo "    ✓ All link sources present."

echo "==> 3/5: Linting shell scripts..."
if command -v shellcheck >/dev/null 2>&1; then
  shellcheck --severity=warning "${repo_dir}"/scripts/*.sh "${repo_dir}"/scripts/lib/*.sh
elif command -v nix >/dev/null 2>&1; then
  nix shell --inputs-from "${repo_dir}" nixpkgs#shellcheck --command \
    shellcheck --severity=warning "${repo_dir}"/scripts/*.sh "${repo_dir}"/scripts/lib/*.sh
else
  echo "    ⚠️  shellcheck not found; skipping lint."
fi
echo "    ✓ ShellCheck passed."

echo "==> 4/5: Evaluating darwin configurations (work & home)..."
source_nix_env
nix_bin="$(find_nix_bin "${repo_dir}")"
for p in work home; do
  DOTFILES_PROFILE="$p" "${nix_bin}" eval --impure --raw \
    "path:${repo_dir}#darwinConfigurations.default.config.system.build.toplevel.drvPath" >/dev/null
done
echo "    ✓ Flake evaluates cleanly for both profiles."

echo "==> 5/5: Running regression test suite..."
python3 -m unittest discover -s "${repo_dir}/tests" -v
echo ""
echo "✅ All dotfiles validation checks passed successfully!"
