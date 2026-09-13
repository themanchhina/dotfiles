#!/usr/bin/env bash
# scripts/lib/remote-tools.sh
# Standalone, zero-sudo installer for essential CLI tools on remote Linux machines.
# Installs to ~/.local/bin using precompiled static/musl binaries.

set -euo pipefail

export DISABLE_AUTO_UPDATE="true"
export OSH_DISABLE_AUTO_UPDATE="true"
export PATH="${HOME}/.local/bin:${HOME}/.local/share/fnm:${PATH}"
mkdir -p "${HOME}/.local/bin" "${HOME}/.local/share"

os="$(uname -s)"
raw_arch="$(uname -m)"

if [[ "${os}" != "Linux" ]]; then
  echo "     ⚠️  Note: Remote tool installer currently targets Linux hosts (detected: ${os})."
fi

# Four naming schemes, one per publisher: musl triples, GOARCH, nvim/lazygit assets, tree-sitter assets.
case "${raw_arch}" in
  x86_64|amd64)
    musl_arch="x86_64"
    go_arch="amd64"
    release_arch="x86_64"
    ts_arch="x64"
    ;;
  aarch64|arm64)
    musl_arch="aarch64"
    go_arch="arm64"
    release_arch="arm64"
    ts_arch="arm64"
    ;;
  *)
    echo "     ❌ Unsupported architecture for automated binary install: ${raw_arch}"
    exit 1
    ;;
esac

# Latest tag from the GitHub web redirect, avoiding the rate-limited API; $2 on failure.
# Must never return non-zero, or set -e kills callers before their fallback line.
latest_github_tag() {
  local tag default="${2:-}"
  tag="$(curl -fsSI "https://github.com/$1/releases/latest" 2>/dev/null \
    | tr -d '\r' \
    | awk -F'/tag/' '/^[Ll]ocation:/ {print $2}')" || tag=""
  echo "${tag:-${default}}"
}

# Already present and runnable? </dev/null is load-bearing: this script arrives on stdin.
# Empty output counts as broken, as in confirm_installed, so a 0-byte binary reinstalls.
report_installed() {
  local name="$1" out
  command -v "${name}" >/dev/null 2>&1 || return 1
  out="$("${name}" --version </dev/null 2>/dev/null)" || return 1
  [[ -n "${out}" ]] || return 1
  echo "     ✓ ${name}: ${out%%$'\n'*}"
}

# Assign inside `if` or set -e aborts here; empty output means a 0-byte binary bash ran as an
# empty script. </dev/null here too: this script arrives on stdin, so a probe can eat it.
confirm_installed() {
  local name="$1"; shift
  local out
  if out="$("$@" </dev/null 2>&1)" && [[ -n "${out}" ]]; then
    echo "     ✓ ${name} installed: ${out%%$'\n'*}"
  else
    echo "     ✗ ${name} installed but not runnable: ${out%%$'\n'*}" >&2
  fi
}

# Extract one named binary out of a .tar.gz release into ~/.local/bin.
install_tarball_bin() {
  local name="$1" url="$2" tmp
  tmp="$(mktemp -d)"
  curl -fsSL "${url}" | tar -xz -C "${tmp}"
  find "${tmp}" -name "${name}" -type f -exec mv {} "${HOME}/.local/bin/${name}" \;
  chmod +x "${HOME}/.local/bin/${name}"
  rm -rf "${tmp}"
  confirm_installed "${name}" "${HOME}/.local/bin/${name}" --version
}

# 1. Neovim (using glibc-2.17 compatible build from neovim-releases)
if ! report_installed nvim; then
  if command -v nvim >/dev/null 2>&1; then
    echo "     ⚠️  Existing nvim binary cannot execute (likely glibc version mismatch). Reinstalling with GLIBC 2.17+ build..."
  fi
  echo "     -> Installing Neovim (${release_arch}) with GLIBC 2.17+ compatibility..."
  nvim_tag="$(latest_github_tag neovim/neovim-releases v0.12.5)"
  if ! curl -fsSL "https://github.com/neovim/neovim-releases/releases/download/${nvim_tag}/nvim-linux-${release_arch}.tar.gz" \
    | tar -xz -C "${HOME}/.local" --strip-components=1 2>/dev/null; then
    echo "     -> Fallback: Downloading standard Neovim release..."
    curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${release_arch}.tar.gz" \
      | tar -xz -C "${HOME}/.local" --strip-components=1
  fi
  confirm_installed nvim "${HOME}/.local/bin/nvim" --version
fi

# 2. Herdr (static-pie linked binary)
if ! report_installed herdr; then
  echo "     -> Installing Herdr..."
  curl -fsSL https://herdr.dev/install.sh | HERDR_INSTALL_DIR="${HOME}/.local/bin" sh
  confirm_installed herdr "${HOME}/.local/bin/herdr" --version
fi

# 3. ripgrep (statically linked musl)
if ! report_installed rg; then
  echo "     -> Installing ripgrep (musl static)..."
  rg_tag="$(latest_github_tag BurntSushi/ripgrep 15.2.0)"
  install_tarball_bin rg \
    "https://github.com/BurntSushi/ripgrep/releases/download/${rg_tag}/ripgrep-${rg_tag#v}-${musl_arch}-unknown-linux-musl.tar.gz"
fi

# 4. fd-find (statically linked musl)
if ! report_installed fd; then
  echo "     -> Installing fd (musl static)..."
  fd_tag="$(latest_github_tag sharkdp/fd v10.5.0)"
  install_tarball_bin fd \
    "https://github.com/sharkdp/fd/releases/download/${fd_tag}/fd-${fd_tag}-${musl_arch}-unknown-linux-musl.tar.gz"
fi

# 5. lazygit (static Go binary)
if ! report_installed lazygit; then
  echo "     -> Installing lazygit..."
  lg_tag="$(latest_github_tag jesseduffield/lazygit v0.65.0)"
  install_tarball_bin lazygit \
    "https://github.com/jesseduffield/lazygit/releases/download/${lg_tag}/lazygit_${lg_tag#v}_linux_${release_arch}.tar.gz"
fi

# 6. jq (single statically linked binary, not a tarball)
if ! report_installed jq; then
  echo "     -> Installing jq..."
  tmp_dir="$(mktemp -d)"
  curl -fsSL -o "${tmp_dir}/jq" "https://github.com/jqlang/jq/releases/latest/download/jq-linux-${go_arch}"
  chmod +x "${tmp_dir}/jq"
  mv "${tmp_dir}/jq" "${HOME}/.local/bin/jq"
  rm -rf "${tmp_dir}"
  confirm_installed jq "${HOME}/.local/bin/jq" --version
fi

# 7. fzf (static Go binary)
if ! report_installed fzf; then
  echo "     -> Installing fzf..."
  fzf_tag="$(latest_github_tag junegunn/fzf v0.74.3)"
  install_tarball_bin fzf \
    "https://github.com/junegunn/fzf/releases/download/${fzf_tag}/fzf-${fzf_tag#v}-linux_${go_arch}.tar.gz"
fi

# 8. uv (Python package manager & runner)
if ! report_installed uv; then
  echo "     -> Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR="${HOME}/.local/bin" sh
  confirm_installed uv "${HOME}/.local/bin/uv" --version
fi

# 9. fnm (Fast Node Manager for Mason / LSPs). Its install dir is already on PATH above.
if ! report_installed fnm; then
  echo "     -> Installing fnm..."
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell --install-dir "${HOME}/.local/share/fnm"
  if [[ -x "${HOME}/.local/share/fnm/fnm" && ! -e "${HOME}/.local/bin/fnm" ]]; then
    ln -sf "${HOME}/.local/share/fnm/fnm" "${HOME}/.local/bin/fnm"
  fi
  confirm_installed fnm "${HOME}/.local/share/fnm/fnm" --version
fi

# 10. tree-sitter CLI. nvim-treesitter's main branch compiles parsers with it and
# wants >= 0.26.1. Every published build needs glibc >= 2.28, so on older hosts
# (Amazon Linux 2 is 2.26) the only route is a source build.
if ! report_installed tree-sitter; then
  echo "     -> Installing tree-sitter CLI..."
  ts_tag="$(latest_github_tag tree-sitter/tree-sitter v0.27.0)"
  tmp_dir="$(mktemp -d)"
  ts_ok=0
  if curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/download/${ts_tag}/tree-sitter-linux-${ts_arch}.gz" \
    | gzip -dc > "${tmp_dir}/tree-sitter" 2>/dev/null && [[ -s "${tmp_dir}/tree-sitter" ]]; then
    chmod +x "${tmp_dir}/tree-sitter"
    # Verify before installing: a binary that cannot run is worse than none, because
    # command -v finds it and Neovim then fails with a bare linker error.
    if "${tmp_dir}/tree-sitter" --version </dev/null >/dev/null 2>&1; then
      mv "${tmp_dir}/tree-sitter" "${HOME}/.local/bin/tree-sitter"
      ts_ok=1
    fi
  fi
  rm -rf "${tmp_dir}"

  if [[ "${ts_ok}" -eq 0 ]]; then
    rm -f "${HOME}/.local/bin/tree-sitter"
    if command -v cargo >/dev/null 2>&1; then
      echo "     ⚠️  Prebuilt tree-sitter needs glibc >= 2.28; building from source (several minutes)..."
      ts_log="${TMPDIR:-/tmp}/tree-sitter-build.log"
      if cargo install --locked tree-sitter-cli >"${ts_log}" 2>&1; then
        ln -sf "${HOME}/.cargo/bin/tree-sitter" "${HOME}/.local/bin/tree-sitter"
        ts_ok=1
      else
        echo "     ✗ cargo install tree-sitter-cli failed. Log: ${ts_log}" >&2
      fi
    else
      echo "     ✗ tree-sitter unavailable: prebuilt needs glibc >= 2.28 and cargo is absent." >&2
      echo "       Neovim treesitter parser compilation will not work on this host." >&2
    fi
  fi

  [[ "${ts_ok}" -eq 1 ]] && confirm_installed tree-sitter "${HOME}/.local/bin/tree-sitter" --version
fi

echo "     ✅ Remote CLI tools check complete!"
