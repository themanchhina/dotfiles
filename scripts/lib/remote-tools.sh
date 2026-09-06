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

case "${raw_arch}" in
  x86_64|amd64)
    arch_x86="x86_64"
    arch_amd="amd64"
    nvim_arch="x86_64"
    lazygit_arch="x86_64"
    ;;
  aarch64|arm64)
    arch_x86="aarch64"
    arch_amd="arm64"
    nvim_arch="arm64"
    lazygit_arch="arm64"
    ;;
  *)
    echo "     ❌ Unsupported architecture for automated binary install: ${raw_arch}"
    exit 1
    ;;
esac

# Fetch latest tag from GitHub web redirect without using rate-limited API
get_latest_github_tag() {
  local repo="$1"
  curl -fsSI "https://github.com/${repo}/releases/latest" 2>/dev/null \
    | tr -d '\r' \
    | awk -F'/tag/' '/^[Ll]ocation:/ {print $2}'
}

# 1. Neovim (using glibc-2.17 compatible build from neovim-releases)
if command -v nvim >/dev/null 2>&1 && nvim --version >/dev/null 2>&1; then
  echo "     ✓ nvim: $(nvim --version | head -n1)"
else
  if command -v nvim >/dev/null 2>&1; then
    echo "     ⚠️  Existing nvim binary cannot execute (likely glibc version mismatch). Reinstalling with GLIBC 2.17+ build..."
  fi
  echo "     -> Installing Neovim (${nvim_arch}) with GLIBC 2.17+ compatibility..."
  nvim_tag="$(get_latest_github_tag "neovim/neovim-releases")"
  nvim_tag="${nvim_tag:-v0.12.5}"
  if ! curl -fsSL "https://github.com/neovim/neovim-releases/releases/download/${nvim_tag}/nvim-linux-${nvim_arch}.tar.gz" \
    | tar -xz -C "${HOME}/.local" --strip-components=1 2>/dev/null; then
    echo "     -> Fallback: Downloading standard Neovim release..."
    curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${nvim_arch}.tar.gz" \
      | tar -xz -C "${HOME}/.local" --strip-components=1
  fi
  echo "     ✓ nvim installed: $(${HOME}/.local/bin/nvim --version | head -n1)"
fi

# 2. Herdr (static-pie linked binary)
if command -v herdr >/dev/null 2>&1 && herdr --version >/dev/null 2>&1; then
  echo "     ✓ herdr: $(herdr --version 2>/dev/null || echo 'installed')"
else
  echo "     -> Installing Herdr..."
  curl -fsSL https://herdr.dev/install.sh | HERDR_INSTALL_DIR="${HOME}/.local/bin" sh
  echo "     ✓ herdr installed: $(${HOME}/.local/bin/herdr --version 2>/dev/null || echo 'installed')"
fi

# 3. ripgrep (rg - statically linked musl)
if command -v rg >/dev/null 2>&1 && rg --version >/dev/null 2>&1; then
  echo "     ✓ rg: $(rg --version | head -n1)"
else
  echo "     -> Installing ripgrep (musl static)..."
  rg_tag="$(get_latest_github_tag "BurntSushi/ripgrep")"
  rg_tag="${rg_tag:-15.2.0}"
  rg_ver="${rg_tag#v}"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/BurntSushi/ripgrep/releases/download/${rg_tag}/ripgrep-${rg_ver}-${arch_x86}-unknown-linux-musl.tar.gz" \
    | tar -xz -C "${tmp_dir}"
  find "${tmp_dir}" -name rg -type f -exec mv {} "${HOME}/.local/bin/rg" \;
  chmod +x "${HOME}/.local/bin/rg"
  rm -rf "${tmp_dir}"
  echo "     ✓ rg installed: $(${HOME}/.local/bin/rg --version | head -n1)"
fi

# 4. fd-find (fd - statically linked musl)
if command -v fd >/dev/null 2>&1 && fd --version >/dev/null 2>&1; then
  echo "     ✓ fd: $(fd --version | head -n1)"
else
  echo "     -> Installing fd (musl static)..."
  fd_tag="$(get_latest_github_tag "sharkdp/fd")"
  fd_tag="${fd_tag:-v10.5.0}"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/sharkdp/fd/releases/download/${fd_tag}/fd-${fd_tag}-${arch_x86}-unknown-linux-musl.tar.gz" \
    | tar -xz -C "${tmp_dir}"
  find "${tmp_dir}" -name fd -type f -exec mv {} "${HOME}/.local/bin/fd" \;
  chmod +x "${HOME}/.local/bin/fd"
  rm -rf "${tmp_dir}"
  echo "     ✓ fd installed: $(${HOME}/.local/bin/fd --version | head -n1)"
fi

# 5. lazygit (static Go binary)
if command -v lazygit >/dev/null 2>&1 && lazygit --version >/dev/null 2>&1; then
  echo "     ✓ lazygit: $(lazygit --version | head -n1)"
else
  echo "     -> Installing lazygit..."
  lg_tag="$(get_latest_github_tag "jesseduffield/lazygit")"
  lg_tag="${lg_tag:-v0.65.0}"
  lg_ver="${lg_tag#v}"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/${lg_tag}/lazygit_${lg_ver}_linux_${lazygit_arch}.tar.gz" \
    | tar -xz -C "${tmp_dir}"
  find "${tmp_dir}" -name lazygit -type f -exec mv {} "${HOME}/.local/bin/lazygit" \;
  chmod +x "${HOME}/.local/bin/lazygit"
  rm -rf "${tmp_dir}"
  echo "     ✓ lazygit installed: $(${HOME}/.local/bin/lazygit --version | head -n1)"
fi

# 6. jq (statically linked binary)
if command -v jq >/dev/null 2>&1 && jq --version >/dev/null 2>&1; then
  echo "     ✓ jq: $(jq --version | head -n1)"
else
  echo "     -> Installing jq..."
  curl -fsSL -o "${HOME}/.local/bin/jq" "https://github.com/jqlang/jq/releases/latest/download/jq-linux-${arch_amd}"
  chmod +x "${HOME}/.local/bin/jq"
  echo "     ✓ jq installed: $(${HOME}/.local/bin/jq --version | head -n1)"
fi

# 7. fzf (static Go binary)
if command -v fzf >/dev/null 2>&1 && fzf --version >/dev/null 2>&1; then
  echo "     ✓ fzf: $(fzf --version | head -n1)"
else
  echo "     -> Installing fzf..."
  fzf_tag="$(get_latest_github_tag "junegunn/fzf")"
  fzf_tag="${fzf_tag:-v0.74.3}"
  fzf_ver="${fzf_tag#v}"
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/junegunn/fzf/releases/download/${fzf_tag}/fzf-${fzf_ver}-linux_${arch_amd}.tar.gz" \
    | tar -xz -C "${tmp_dir}"
  find "${tmp_dir}" -name fzf -type f -exec mv {} "${HOME}/.local/bin/fzf" \;
  chmod +x "${HOME}/.local/bin/fzf"
  rm -rf "${tmp_dir}"
  echo "     ✓ fzf installed: $(${HOME}/.local/bin/fzf --version | head -n1)"
fi

# 8. uv (Python package manager & runner)
if command -v uv >/dev/null 2>&1 && uv --version >/dev/null 2>&1; then
  echo "     ✓ uv: $(uv --version | head -n1)"
else
  echo "     -> Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR="${HOME}/.local/bin" sh
  echo "     ✓ uv installed: $(${HOME}/.local/bin/uv --version 2>/dev/null || echo 'installed')"
fi

# 9. fnm (Fast Node Manager for Mason / LSPs)
if (command -v fnm >/dev/null 2>&1 || [[ -x "${HOME}/.local/share/fnm/fnm" ]]) && fnm --version >/dev/null 2>&1; then
  echo "     ✓ fnm: $(fnm --version 2>/dev/null || echo 'installed')"
else
  echo "     -> Installing fnm..."
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell --install-dir "${HOME}/.local/share/fnm"
  if [[ -x "${HOME}/.local/share/fnm/fnm" && ! -e "${HOME}/.local/bin/fnm" ]]; then
    ln -sf "${HOME}/.local/share/fnm/fnm" "${HOME}/.local/bin/fnm"
  fi
  echo "     ✓ fnm installed"
fi

# 10. zoxide (Smarter cd - musl static)
if command -v zoxide >/dev/null 2>&1 && zoxide --version >/dev/null 2>&1; then
  echo "     ✓ zoxide: $(zoxide --version | head -n1)"
else
  echo "     -> Installing zoxide..."
  curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
  echo "     ✓ zoxide installed: $(${HOME}/.local/bin/zoxide --version 2>/dev/null || echo 'installed')"
fi

echo "     ✅ Remote CLI tools check complete!"
