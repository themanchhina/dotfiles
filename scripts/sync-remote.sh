#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

usage() {
  cat << EOF
Usage: $(basename "$0") <ssh-host> [options]

Syncs essential configuration files to a remote machine over SSH:
  - Herdr: ~/.config/herdr/config.toml (theme, status symbols, 10MB scrollback, terminal notifications)
  - Neovim: ~/.config/nvim/ (init.lua, lazy-lock.json, plugins, keymaps)
  - Git: ~/.gitconfig, ~/.config/git/{ignore,personal.conf}
  - Zsh: ~/.zsh_aliases (agent shortcuts gi/co/cc, git worktree helpers)
  - Shell: sets PATH (~/.local/bin), TERM_PROGRAM=WezTerm & sources aliases in remote ~/.zshrc / ~/.bashrc
  - Herdr Server: automatically reloads herdr server config on the remote machine

Arguments:
  <ssh-host>           SSH host name (e.g. 'india', 'home', or 'user@host.com')

Options:
  -t, --install-tools  Install missing CLI tools (nvim, herdr, rg, fd, lazygit, jq, fzf, uv, fnm, zoxide) via curl into ~/.local/bin
  --clean              Purge remote Neovim plugin cache and reinstall fresh from lockfile
  --dry-run            Show what would be copied without making changes
  -h, --help           Show this help message

Examples:
  $(basename "$0") india
  $(basename "$0") india --install-tools
  $(basename "$0") home --install-tools --clean
  $(basename "$0") daman@server.example.com
EOF
  exit "${1:-1}"
}

if [[ $# -lt 1 ]]; then
  usage 1
elif [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
  usage 0
fi

target_host="$1"
shift

install_tools=0
dry_run=0
clean=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--install-tools|--tools)
      install_tools=1
      shift
      ;;
    --clean)
      clean=1
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

echo "==> Testing SSH connection to '${target_host}'..."
if ! ssh -q -o BatchMode=yes -o ConnectTimeout=8 "${target_host}" exit 2>/dev/null; then
  if ! ssh -o ConnectTimeout=8 "${target_host}" exit; then
    echo "Error: Could not connect to '${target_host}' over SSH." >&2
    exit 1
  fi
fi

echo "==> Preparing remote directories on '${target_host}'..."
if [[ ${dry_run} -eq 0 ]]; then
  ssh "${target_host}" "mkdir -p ~/.config/herdr ~/.config/git ~/.config/nvim ~/.ssh ~/.local/bin ~/.local/share"
fi

# Optional: Install essential CLI tools in user-space (~/.local/bin) via curl
if [[ ${install_tools} -eq 1 ]]; then
  echo "==> Checking and installing essential CLI tools on '${target_host}'..."
  if [[ ${dry_run} -eq 1 ]]; then
    echo "     [dry-run] Check and install nvim, herdr, rg, fd, lazygit, jq, fzf, uv, fnm, zoxide into ~/.local/bin"
  else
    ssh "${target_host}" 'bash -s' << 'REMOTE_TOOL_INSTALLER'
      set -euo pipefail

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
          ;;
        aarch64|arm64)
          arch_x86="aarch64"
          arch_amd="arm64"
          nvim_arch="arm64"
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

      # 1. Neovim (nvim >= 0.10)
      if command -v nvim >/dev/null 2>&1; then
        echo "     ✓ nvim: $(nvim --version | head -n1)"
      else
        echo "     -> Installing Neovim (${nvim_arch})..."
        curl -fsSL "https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${nvim_arch}.tar.gz" \
          | tar -xz -C "${HOME}/.local" --strip-components=1
        echo "     ✓ nvim installed: $(${HOME}/.local/bin/nvim --version | head -n1)"
      fi

      # 2. Herdr
      if command -v herdr >/dev/null 2>&1; then
        echo "     ✓ herdr: $(herdr --version 2>/dev/null || echo 'installed')"
      else
        echo "     -> Installing Herdr..."
        curl -fsSL https://herdr.dev/install.sh | sh
        echo "     ✓ herdr installed: $(${HOME}/.local/bin/herdr --version 2>/dev/null || echo 'installed')"
      fi

      # 3. ripgrep (rg)
      if command -v rg >/dev/null 2>&1; then
        echo "     ✓ rg: $(rg --version | head -n1)"
      else
        echo "     -> Installing ripgrep..."
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

      # 4. fd-find (fd)
      if command -v fd >/dev/null 2>&1; then
        echo "     ✓ fd: $(fd --version | head -n1)"
      else
        echo "     -> Installing fd..."
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

      # 5. lazygit
      if command -v lazygit >/dev/null 2>&1; then
        echo "     ✓ lazygit: $(lazygit --version | head -n1)"
      else
        echo "     -> Installing lazygit..."
        lg_tag="$(get_latest_github_tag "jesseduffield/lazygit")"
        lg_tag="${lg_tag:-v0.65.0}"
        lg_ver="${lg_tag#v}"
        tmp_dir="$(mktemp -d)"
        curl -fsSL "https://github.com/jesseduffield/lazygit/releases/download/${lg_tag}/lazygit_${lg_ver}_linux_${arch_amd}.tar.gz" \
          | tar -xz -C "${tmp_dir}"
        find "${tmp_dir}" -name lazygit -type f -exec mv {} "${HOME}/.local/bin/lazygit" \;
        chmod +x "${HOME}/.local/bin/lazygit"
        rm -rf "${tmp_dir}"
        echo "     ✓ lazygit installed: $(${HOME}/.local/bin/lazygit --version | head -n1)"
      fi

      # 6. jq
      if command -v jq >/dev/null 2>&1; then
        echo "     ✓ jq: $(jq --version | head -n1)"
      else
        echo "     -> Installing jq..."
        curl -fsSL -o "${HOME}/.local/bin/jq" "https://github.com/jqlang/jq/releases/latest/download/jq-linux-${arch_amd}"
        chmod +x "${HOME}/.local/bin/jq"
        echo "     ✓ jq installed: $(${HOME}/.local/bin/jq --version | head -n1)"
      fi

      # 7. fzf
      if command -v fzf >/dev/null 2>&1; then
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
      if command -v uv >/dev/null 2>&1; then
        echo "     ✓ uv: $(uv --version | head -n1)"
      else
        echo "     -> Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh
        echo "     ✓ uv installed: $(${HOME}/.local/bin/uv --version 2>/dev/null || echo 'installed')"
      fi

      # 9. fnm (Fast Node Manager for Mason / LSPs)
      if command -v fnm >/dev/null 2>&1 || [[ -x "${HOME}/.local/share/fnm/fnm" ]]; then
        echo "     ✓ fnm: installed"
      else
        echo "     -> Installing fnm..."
        curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell --install-dir "${HOME}/.local/share/fnm"
        if [[ -x "${HOME}/.local/share/fnm/fnm" && ! -e "${HOME}/.local/bin/fnm" ]]; then
          ln -sf "${HOME}/.local/share/fnm/fnm" "${HOME}/.local/bin/fnm"
        fi
        echo "     ✓ fnm installed"
      fi

      # 10. zoxide (Smarter cd)
      if command -v zoxide >/dev/null 2>&1; then
        echo "     ✓ zoxide: $(zoxide --version | head -n1)"
      else
        echo "     -> Installing zoxide..."
        curl -sSfL https://raw.githubusercontent.com/ajeetdsouza/zoxide/main/install.sh | sh
        echo "     ✓ zoxide installed: $(${HOME}/.local/bin/zoxide --version 2>/dev/null || echo 'installed')"
      fi

      echo "     ✅ Remote CLI tools check complete!"
REMOTE_TOOL_INSTALLER
  fi
fi

echo "==> Syncing configs to '${target_host}'..."

# 1. Herdr config
echo "  -> Herdr: config/herdr/config.toml"
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] scp ${repo_dir}/config/herdr/config.toml ${target_host}:~/.config/herdr/config.toml"
else
  scp -q "${repo_dir}/config/herdr/config.toml" "${target_host}:~/.config/herdr/config.toml"
fi

# 2. Neovim config
echo "  -> Neovim: config/nvim/"
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] rsync -az --delete --exclude='.git' ${repo_dir}/config/nvim/ ${target_host}:~/.config/nvim/"
else
  if ssh "${target_host}" "command -v rsync >/dev/null 2>&1"; then
    rsync -az --delete --exclude='.git' "${repo_dir}/config/nvim/" "${target_host}:~/.config/nvim/"
  else
    # Fallback to tar stream over ssh if rsync is not installed on remote (clean first to avoid ghost files)
    ssh "${target_host}" "rm -rf ~/.config/nvim && mkdir -p ~/.config/nvim"
    (cd "${repo_dir}/config/nvim" && tar -cf - .) | ssh "${target_host}" "tar -xf - -C ~/.config/nvim"
  fi

  # Clean up stale legacy treesitter files and restore lockfile commits headlessly
  if [[ ${dry_run} -eq 1 ]]; then
    if [[ ${clean} -eq 1 ]]; then
      echo "     [dry-run] remote: rm -rf ~/.local/share/nvim/lazy ~/.local/share/nvim/site ~/.cache/nvim ~/.local/state/nvim"
    fi
    echo "     [dry-run] remote: nvim --headless '+Lazy! restore' '+qa'"
  else
    ssh "${target_host}" "bash -s -- ${clean}" << 'REMOTE_NVIM_SYNC'
      export PATH="${HOME}/.local/bin:${PATH}"
      clean_mode="$1"
      if [[ "${clean_mode}" == "1" ]]; then
        echo "     ==> Purging remote plugin caches (~/.local/share/nvim/lazy, site, cache)..."
        rm -rf ~/.local/share/nvim/lazy ~/.local/share/nvim/site ~/.cache/nvim ~/.local/state/nvim
      fi
      rm -f "${HOME}/.local/share/nvim/lazy/nvim-treesitter/lua/nvim-treesitter.lua"
      if [[ -d "${HOME}/.local/share/nvim/lazy/nvim-treesitter/parser" ]]; then
        rm -rf "${HOME}/.local/share/nvim/lazy/nvim-treesitter/parser"
      fi
      if command -v nvim >/dev/null 2>&1; then
        echo "     ==> Restoring Neovim plugins headlessly to match lockfile..."
        nvim --headless "+Lazy! restore" "+qa" >/dev/null 2>&1 || true
      fi
REMOTE_NVIM_SYNC
  fi
fi

# 3. Git configs
echo "  -> Git: .gitconfig, personal.conf, ignore"
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] scp git configs"
else
  scp -q "${repo_dir}/config/git/config" "${target_host}:~/.gitconfig"
  scp -q "${repo_dir}/config/git/personal.conf" "${target_host}:~/.config/git/personal.conf"
  scp -q "${repo_dir}/config/git/ignore" "${target_host}:~/.config/git/ignore"
fi

# 4. Zsh aliases
echo "  -> Zsh: .zsh_aliases"
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] scp ${repo_dir}/config/zsh/zsh_aliases ${target_host}:~/.zsh_aliases"
else
  scp -q "${repo_dir}/config/zsh/zsh_aliases" "${target_host}:~/.zsh_aliases"
fi

# 5. Remote shell hooks (PATH, TERM_PROGRAM & aliases sourcing)
echo "  -> Ensuring remote shell environment (PATH, TERM_PROGRAM=WezTerm & alias sourcing)..."
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] add ~/.local/bin to PATH, TERM_PROGRAM, and zsh_aliases sourcing to remote shell profiles"
else
  ssh "${target_host}" 'bash -s' << 'REMOTE_SCRIPT'
    # For zsh:
    if [[ -f ~/.zshrc || ! -f ~/.bashrc ]]; then
      touch ~/.zshrc
      if ! grep -q '\.local/bin' ~/.zshrc 2>/dev/null; then
        printf '\n# User local binaries\nexport PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$PATH"\n' >> ~/.zshrc
      fi
      if ! grep -q 'TERM_PROGRAM.*WezTerm' ~/.zshrc 2>/dev/null; then
        printf '\n# Ensure terminal identity for Herdr notifications\nexport TERM_PROGRAM="${TERM_PROGRAM:-WezTerm}"\n' >> ~/.zshrc
      fi
      if ! grep -q 'zsh_aliases' ~/.zshrc 2>/dev/null; then
        printf '[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases\n' >> ~/.zshrc
      fi
    fi

    # For bash:
    if [[ -f ~/.bashrc ]]; then
      if ! grep -q '\.local/bin' ~/.bashrc 2>/dev/null; then
        printf '\n# User local binaries\nexport PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$PATH"\n' >> ~/.bashrc
      fi
      if ! grep -q 'TERM_PROGRAM.*WezTerm' ~/.bashrc 2>/dev/null; then
        printf '\n# Ensure terminal identity for Herdr notifications\nexport TERM_PROGRAM="${TERM_PROGRAM:-WezTerm}"\n' >> ~/.bashrc
      fi
      if ! grep -q 'zsh_aliases' ~/.bashrc 2>/dev/null; then
        printf '[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases\n' >> ~/.bashrc
      fi
    fi
REMOTE_SCRIPT
fi

# 6. Reload running Herdr server if present
echo "  -> Checking for running Herdr server on '${target_host}'..."
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] herdr server reload-config"
else
  reload_result=$(ssh "${target_host}" 'export PATH="$HOME/.local/bin:$PATH"; command -v herdr >/dev/null 2>&1 && herdr server reload-config 2>&1 || true')
  if [[ -n "${reload_result}" && "${reload_result}" =~ "applied" ]]; then
    echo "     ✅ Remote Herdr server reloaded with new config!"
  elif [[ -n "${reload_result}" ]]; then
    echo "     ℹ️  Herdr: ${reload_result}"
  fi
fi

echo "==> Successfully synced configs to '${target_host}'!"
