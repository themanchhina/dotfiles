#!/usr/bin/env bash
# Install remote Linux CLI tools in user-space without sudo.

set -euo pipefail

export DISABLE_AUTO_UPDATE="true"
export OSH_DISABLE_AUTO_UPDATE="true"
export PATH="${HOME}/.local/bin:${HOME}/.local/share/fnm:${PATH}"

os="$(uname -s)"
raw_arch="$(uname -m)"

if [[ "${os}" != "Linux" ]]; then
  echo "Error: Remote tool installation requires Linux (detected: ${os})." >&2
  exit 1
fi

for tool in curl tar gzip git unzip sha256sum; do
  command -v "${tool}" >/dev/null 2>&1 || { echo "Error: Install ${tool} on the remote host first." >&2; exit 1; }
done
if ! command -v cc >/dev/null 2>&1 && ! command -v gcc >/dev/null 2>&1 && ! command -v clang >/dev/null 2>&1; then
  echo "Error: A C compiler is required to build Neovim treesitter parsers." >&2
  exit 1
fi
mkdir -p "${HOME}/.local/bin" "${HOME}/.local/share"

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

# Probes must not consume this script's stdin; empty executables do not count as installed.
report_installed() {
  local name="$1" out
  command -v "${name}" >/dev/null 2>&1 || return 1
  out="$("${name}" --version </dev/null 2>/dev/null)" || return 1
  [[ -n "${out}" ]] || return 1
  echo "     ✓ ${name}: ${out%%$'\n'*}"
}

confirm_installed() {
  local name="$1"; shift
  local out
  if out="$("$@" </dev/null 2>&1)" && [[ -n "${out}" ]]; then
    echo "     ✓ ${name} installed: ${out%%$'\n'*}"
  else
    echo "     ✗ ${name} installed but not runnable: ${out%%$'\n'*}" >&2
    return 1
  fi
}

nvim_ready() {
  local bin="${1:-nvim}" version
  version="$("${bin}" --version </dev/null 2>/dev/null)" || return 1
  [[ "${version}" == NVIM\ v* ]] || return 1
  "${bin}" --headless --clean -i NONE -n \
    -c 'lua if vim.fn.has("nvim-0.11.2") ~= 1 or not jit or vim.v.errmsg ~= "" then vim.cmd("cquit") end' \
    -c qa </dev/null >/dev/null 2>&1
}

# Keep the distribution separate from ~/.local/share/nvim user/plugin data.
# A fresh tree prevents removed runtime files surviving upgrades or downgrades.
install_nvim_archive() {
  (
    mkdir -p "${HOME}/.local/opt" || exit 1
    stage="$(mktemp -d "${HOME}/.local/opt/nvim.XXXXXX")" || exit 1
    trap 'rm -rf "$stage"' EXIT
    curl -fsSL "$1" | tar -xz -C "$stage" --strip-components=1 || exit 1
    nvim_ready "$stage/bin/nvim" || exit 1
    rm -rf "${HOME}/.local/opt/nvim" || exit 1
    mv "$stage" "${HOME}/.local/opt/nvim" || exit 1
    ln -sfn "${HOME}/.local/opt/nvim/bin/nvim" "${HOME}/.local/bin/nvim.new" &&
      mv -f "${HOME}/.local/bin/nvim.new" "${HOME}/.local/bin/nvim"
  )
}

tree_sitter_ready() {
  local bin="${1:-tree-sitter}" out version major minor patch
  out="$("${bin}" --version </dev/null 2>/dev/null)" || return 1
  version="${out#tree-sitter }"
  version="${version%% *}"
  IFS=. read -r major minor patch <<< "${version}"
  [[ "${major}" =~ ^[0-9]+$ && "${minor}" =~ ^[0-9]+$ && "${patch}" =~ ^[0-9]+$ ]] || return 1
  (( major > 0 || minor > 26 || (minor == 26 && patch >= 1) ))
}

install_tarball_bin() {
  local name="$1" url="$2" tmp
  tmp="$(mktemp -d)"
  curl -fsSL "${url}" | tar -xz -C "${tmp}"
  find "${tmp}" -name "${name}" -type f -exec mv {} "${HOME}/.local/bin/${name}" \;
  chmod +x "${HOME}/.local/bin/${name}"
  rm -rf "${tmp}"
  confirm_installed "${name}" "${HOME}/.local/bin/${name}" --version
}

# Try the same Neovim release's older-glibc build if upstream cannot run.
if ! nvim_ready; then
  if command -v nvim >/dev/null 2>&1; then
    echo "     ⚠️  Existing Neovim does not meet the >= 0.11.2 with LuaJIT requirement. Reinstalling..."
  fi
  echo "     -> Installing upstream stable Neovim (${release_arch})..."
  nvim_tag="$(latest_github_tag neovim/neovim v0.12.5)"
  if ! install_nvim_archive "https://github.com/neovim/neovim/releases/download/${nvim_tag}/nvim-linux-${release_arch}.tar.gz"; then
    echo "     -> Fallback: Downloading the older-glibc compatibility build..."
    install_nvim_archive "https://github.com/neovim/neovim-releases/releases/download/${nvim_tag}/nvim-linux-${release_arch}.tar.gz"
  fi
  hash -r
  nvim_ready || { echo "Error: Installed Neovim does not meet the version and LuaJIT requirements." >&2; exit 1; }
  confirm_installed nvim "${HOME}/.local/bin/nvim" --version
fi

if ! report_installed rg; then
  echo "     -> Installing ripgrep (musl static)..."
  rg_tag="$(latest_github_tag BurntSushi/ripgrep 15.2.0)"
  install_tarball_bin rg \
    "https://github.com/BurntSushi/ripgrep/releases/download/${rg_tag}/ripgrep-${rg_tag#v}-${musl_arch}-unknown-linux-musl.tar.gz"
fi

if ! report_installed fd; then
  echo "     -> Installing fd (musl static)..."
  fd_tag="$(latest_github_tag sharkdp/fd v10.5.0)"
  install_tarball_bin fd \
    "https://github.com/sharkdp/fd/releases/download/${fd_tag}/fd-${fd_tag}-${musl_arch}-unknown-linux-musl.tar.gz"
fi

if ! report_installed lazygit; then
  echo "     -> Installing lazygit..."
  lg_tag="$(latest_github_tag jesseduffield/lazygit v0.65.0)"
  install_tarball_bin lazygit \
    "https://github.com/jesseduffield/lazygit/releases/download/${lg_tag}/lazygit_${lg_tag#v}_linux_${release_arch}.tar.gz"
fi

if ! report_installed jq; then
  echo "     -> Installing jq..."
  tmp_dir="$(mktemp -d)"
  curl -fsSL -o "${tmp_dir}/jq" "https://github.com/jqlang/jq/releases/latest/download/jq-linux-${go_arch}"
  chmod +x "${tmp_dir}/jq"
  mv "${tmp_dir}/jq" "${HOME}/.local/bin/jq"
  rm -rf "${tmp_dir}"
  confirm_installed jq "${HOME}/.local/bin/jq" --version
fi

# Match the Mac's Herdr version for client/server compatibility.
herdr_version="${1:-}"
[[ "${herdr_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]] || { echo "Error: Invalid or missing Herdr version." >&2; exit 1; }
if [[ "$(herdr --version </dev/null 2>/dev/null || true)" != "herdr ${herdr_version}" ]]; then
  echo "     -> Installing Herdr ${herdr_version} to match the Mac..."
  (
    tmp_dir="$(mktemp -d)"
    trap 'rm -rf "$tmp_dir"' EXIT
    asset="herdr-linux-${musl_arch}"
    digest="$(curl -fsSL "https://api.github.com/repos/herdrdev/herdr/releases/tags/v${herdr_version}" \
      | jq -er --arg asset "${asset}" '.assets[] | select(.name == $asset) | .digest')"
    [[ "${digest}" =~ ^sha256:[a-f0-9]{64}$ ]] || { echo "Error: Missing Herdr asset checksum." >&2; exit 1; }
    curl -fsSL "https://github.com/herdrdev/herdr/releases/download/v${herdr_version}/${asset}" -o "${tmp_dir}/herdr"
    printf '%s  %s\n' "${digest#sha256:}" "${tmp_dir}/herdr" | sha256sum -c -
    chmod +x "${tmp_dir}/herdr"
    [[ "$("${tmp_dir}/herdr" --version </dev/null)" == "herdr ${herdr_version}" ]] || { echo "Error: Herdr version mismatch." >&2; exit 1; }
    mv "${tmp_dir}/herdr" "${HOME}/.local/bin/herdr"
  )
fi

# fzf 0.48+ embeds the shell integration used by sync-remote.sh.
if ! report_installed fzf || ! fzf --bash </dev/null >/dev/null 2>&1; then
  echo "     -> Installing fzf..."
  fzf_tag="$(latest_github_tag junegunn/fzf v0.74.3)"
  install_tarball_bin fzf \
    "https://github.com/junegunn/fzf/releases/download/${fzf_tag}/fzf-${fzf_tag#v}-linux_${go_arch}.tar.gz"
fi

if ! report_installed direnv; then
  echo "     -> Installing direnv..."
  tmp_dir="$(mktemp -d)"
  curl -fsSL "https://github.com/direnv/direnv/releases/latest/download/direnv.linux-${go_arch}" -o "${tmp_dir}/direnv"
  chmod +x "${tmp_dir}/direnv"
  confirm_installed direnv "${tmp_dir}/direnv" --version
  mv "${tmp_dir}/direnv" "${HOME}/.local/bin/direnv"
  rm -rf "${tmp_dir}"
fi

if ! report_installed uv; then
  echo "     -> Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR="${HOME}/.local/bin" sh
  confirm_installed uv "${HOME}/.local/bin/uv" --version
fi

if ! report_installed fnm; then
  echo "     -> Installing fnm..."
  curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell --install-dir "${HOME}/.local/share/fnm"
  if [[ -x "${HOME}/.local/share/fnm/fnm" && ! -e "${HOME}/.local/bin/fnm" ]]; then
    ln -sf "${HOME}/.local/share/fnm/fnm" "${HOME}/.local/bin/fnm"
  fi
  confirm_installed fnm "${HOME}/.local/share/fnm/fnm" --version
fi

# Build tree-sitter locally if the prebuilt needs a newer glibc than the host provides.
if ! tree_sitter_ready; then
  echo "     -> Installing tree-sitter CLI..."
  ts_tag="$(latest_github_tag tree-sitter/tree-sitter v0.27.0)"
  tmp_dir="$(mktemp -d)"
  ts_ok=0
  if curl -fsSL "https://github.com/tree-sitter/tree-sitter/releases/download/${ts_tag}/tree-sitter-linux-${ts_arch}.gz" \
    | gzip -dc > "${tmp_dir}/tree-sitter" 2>/dev/null && [[ -s "${tmp_dir}/tree-sitter" ]]; then
    chmod +x "${tmp_dir}/tree-sitter"
    # Do not put an unrunnable binary on Neovim's PATH.
    if tree_sitter_ready "${tmp_dir}/tree-sitter"; then
      mv "${tmp_dir}/tree-sitter" "${HOME}/.local/bin/tree-sitter"
      ts_ok=1
    fi
  fi
  rm -rf "${tmp_dir}"

  if [[ "${ts_ok}" -eq 0 ]]; then
    rm -f "${HOME}/.local/bin/tree-sitter"
    echo "     -> Prebuilt tree-sitter cannot run; building it for the local libc..."
    (
      build_dir="$(mktemp -d)"
      trap 'rm -rf "$build_dir"' EXIT
      export CARGO_TARGET_DIR="${build_dir}/target"
      cargo_bin="$(command -v cargo || true)"
      if [[ -z "${cargo_bin}" ]]; then
        export CARGO_HOME="${build_dir}/cargo" RUSTUP_HOME="${build_dir}/rustup"
        curl --proto '=https' --tlsv1.2 -fsSL https://sh.rustup.rs \
          | sh -s -- -y --profile minimal --no-modify-path
        cargo_bin="${CARGO_HOME}/bin/cargo"
      fi
      "${cargo_bin}" install --locked --version "${ts_tag#v}" --root "${build_dir}/install" tree-sitter-cli </dev/null
      cp "${build_dir}/install/bin/tree-sitter" "${HOME}/.local/bin/tree-sitter"
    )
    ts_ok=1
  fi

  [[ "${ts_ok}" -eq 1 ]] && tree_sitter_ready "${HOME}/.local/bin/tree-sitter"
fi

tree_sitter_ready || { echo "Error: tree-sitter >= 0.26.1 is required." >&2; exit 1; }

nvim_ready || { echo "Error: Neovim must be >= 0.11.2 and use LuaJIT." >&2; exit 1; }

echo "     ✅ Remote CLI tools check complete!"
