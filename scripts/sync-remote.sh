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
if ! ssh -q -T -o BatchMode=yes -o ConnectTimeout=8 "${target_host}" exit 2>/dev/null; then
  if ! ssh -T -o ConnectTimeout=8 "${target_host}" exit; then
    echo "Error: Could not connect to '${target_host}' over SSH." >&2
    exit 1
  fi
fi

echo "==> Preparing remote directories on '${target_host}'..."
if [[ ${dry_run} -eq 0 ]]; then
  ssh -T "${target_host}" '
    rm -rf ~/.oh-my-bash/log/update.lock 2>/dev/null || true
    mkdir -p ~/.config/herdr ~/.config/git ~/.config/nvim ~/.ssh ~/.local/bin ~/.local/share
  ' </dev/null
fi

# Optional: Install essential CLI tools in user-space (~/.local/bin) via curl
if [[ ${install_tools} -eq 1 ]]; then
  echo "==> Checking and installing essential CLI tools on '${target_host}'..."
  remote_installer=".remote-tools-$$.sh"
  if [[ ${dry_run} -eq 1 ]]; then
    echo "     [dry-run] scp ${repo_dir}/scripts/lib/remote-tools.sh ${target_host}:~/${remote_installer}"
    echo "     [dry-run] ssh -T ${target_host} 'bash ~/${remote_installer} </dev/null; rm -f ~/${remote_installer}'"
  else
    scp -q "${repo_dir}/scripts/lib/remote-tools.sh" "${target_host}:~/${remote_installer}"
    ssh -T "${target_host}" "bash -c 'trap \"rm -f ~/${remote_installer}\" EXIT INT TERM; bash ~/${remote_installer}' </dev/null"
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
  if ssh -T "${target_host}" "command -v rsync >/dev/null 2>&1" </dev/null; then
    rsync -az --delete --exclude='.git' "${repo_dir}/config/nvim/" "${target_host}:~/.config/nvim/"
  else
    # Fallback to tar stream over ssh if rsync is not installed on remote (clean first to avoid ghost files)
    ssh -T "${target_host}" "rm -rf ~/.config/nvim && mkdir -p ~/.config/nvim" </dev/null
    (cd "${repo_dir}/config/nvim" && tar -cf - .) | ssh -T "${target_host}" "tar -xf - -C ~/.config/nvim"
  fi

  # Clean up stale legacy treesitter files and restore lockfile commits headlessly
  if [[ ${dry_run} -eq 1 ]]; then
    if [[ ${clean} -eq 1 ]]; then
      echo "     [dry-run] remote: rm -rf ~/.local/share/nvim/lazy ~/.local/share/nvim/site ~/.cache/nvim ~/.local/state/nvim"
    fi
    echo "     [dry-run] remote: nvim --headless '+Lazy! restore' '+qa'"
  else
    ssh -T "${target_host}" "bash -s -- ${clean}" << 'REMOTE_NVIM_SYNC'
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
        nvim --headless "+Lazy! restore" "+qa" </dev/null >/dev/null 2>&1 || true
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
  ssh -T "${target_host}" 'bash -s' << 'REMOTE_SCRIPT'
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
  reload_result=$(ssh -T "${target_host}" 'export PATH="$HOME/.local/bin:$PATH"; command -v herdr >/dev/null 2>&1 && herdr server reload-config 2>&1 || true' </dev/null)
  if [[ -n "${reload_result}" && "${reload_result}" =~ "applied" ]]; then
    echo "     ✅ Remote Herdr server reloaded with new config!"
  elif [[ -n "${reload_result}" ]]; then
    echo "     ℹ️  Herdr: ${reload_result}"
  fi
fi

echo "==> Successfully synced configs to '${target_host}'!"
