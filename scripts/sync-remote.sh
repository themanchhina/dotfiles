#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck disable=SC1091
source "${repo_dir}/scripts/lib/utils.sh" # validate_profile only; the rest act on this Mac

usage() {
  cat << EOF
Usage: $(basename "$0") <ssh-host> [options]

Syncs essential configuration files to a remote machine over SSH:
  - Herdr: ~/.config/herdr/config.toml (theme, status symbols, 10MB scrollback, terminal notifications)
  - Neovim: ~/.config/nvim/ (init.lua, lazy-lock.json, plugins, keymaps)
  - Git: ~/.gitconfig, ~/.config/git/{ignore,personal.conf}, and a generated
         ~/.config/git/local.conf (owned by this script: clears the macOS
         credential helper; applies the personal identity only with
         --profile home, so a work host keeps its own identity)
  - Zsh: ~/.zsh_aliases (agent shortcuts gi/co/cc, docker wrappers, editor aliases)
  - Agent: ~/.claude/AGENTS.md (standing coding-agent instructions; skipped when the
           remote already symlinks it into a checkout, so live edits keep working)
  - Shell: sets PATH (~/.local/bin), EDITOR=nvim, TERM_PROGRAM=WezTerm & sources
           aliases in remote ~/.zshrc / ~/.bashrc
  - Herdr Server: automatically reloads herdr server config on the remote machine

Arguments:
  <ssh-host>           SSH host name (e.g. 'india', 'home', or 'user@host.com')

Options:
  -t, --install-tools, --tools
                       Install missing CLI tools (nvim, herdr, rg, fd, lazygit, jq, fzf, uv, fnm, tree-sitter) via curl into ~/.local/bin
  --profile NAME       work (default) or home. "home" applies the personal Git
                       identity on the remote; "work" leaves identity unset so
                       commits fail loudly rather than using a personal address
  --clean, -c          Purge remote Neovim plugin cache and reinstall fresh from lockfile
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
profile="work"
while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--install-tools|--tools)
      install_tools=1
      shift
      ;;
    --clean|-c)
      clean=1
      shift
      ;;
    --profile)
      [[ $# -ge 2 ]] || { echo "Error: --profile requires a value." >&2; exit 1; }
      profile="$2"
      shift 2
      ;;
    --profile=*)
      profile="${1#*=}"
      shift
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      ;;
  esac
done

# Empty is a valid "use the default" elsewhere, but this script has no default-fill.
[[ -n "${profile}" ]] || { echo "Error: --profile requires a value." >&2; exit 1; }
validate_profile "${profile}" || exit 1

echo "==> Testing SSH connection to '${target_host}'..."
if ! ssh -q -T -o BatchMode=yes -o ConnectTimeout=8 "${target_host}" exit 2>/dev/null; then
  if ! ssh -T -o ConnectTimeout=8 "${target_host}" exit; then
    echo "Error: Could not connect to '${target_host}' over SSH." >&2
    exit 1
  fi
fi

echo "==> Preparing remote directories on '${target_host}'..."
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] remote: rm -f ~/.oh-my-bash/log/update.lock"
  echo "     [dry-run] remote: mkdir -p ~/.config/herdr ~/.config/git ~/.config/nvim ~/.local/bin ~/.local/share ~/.claude"
else
  ssh -T "${target_host}" '
    rm -f ~/.oh-my-bash/log/update.lock 2>/dev/null || true
    mkdir -p ~/.config/herdr ~/.config/git ~/.config/nvim ~/.local/bin ~/.local/share ~/.claude
  ' </dev/null
fi

# Optional: Install essential CLI tools in user-space (~/.local/bin) via curl
if [[ ${install_tools} -eq 1 ]]; then
  echo "==> Checking and installing essential CLI tools on '${target_host}'..."
  # Fed on stdin, never scp'd: a predictable remote ~/.remote-tools-$$.sh can be a pre-planted symlink.
  if [[ ${dry_run} -eq 1 ]]; then
    echo "     [dry-run] ssh -T ${target_host} 'bash -s' < ${repo_dir}/scripts/lib/remote-tools.sh"
  else
    ssh -T "${target_host}" 'bash -s' < "${repo_dir}/scripts/lib/remote-tools.sh"
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
  echo "     [dry-run] remote: rm -rf ~/.config/nvim.tmp"
  echo "     [dry-run] scp -r ${repo_dir}/config/nvim ${target_host}:~/.config/nvim.tmp"
  echo "     [dry-run] remote: rm -rf ~/.config/nvim   <-- DELETES the remote config, no backup"
  echo "     [dry-run] remote: mv ~/.config/nvim.tmp ~/.config/nvim"
  if [[ ${clean} -eq 1 ]]; then
    echo "     [dry-run] remote: rm -rf ~/.local/share/nvim/lazy ~/.local/share/nvim/site ~/.cache/nvim"
  fi
  echo "     [dry-run] remote: nvim --headless '+Lazy! restore' '+qa'"
else
  ssh -T "${target_host}" "rm -rf ~/.config/nvim.tmp" </dev/null
  scp -q -r "${repo_dir}/config/nvim" "${target_host}:~/.config/nvim.tmp"
  ssh -T "${target_host}" "rm -rf ~/.config/nvim && mv ~/.config/nvim.tmp ~/.config/nvim" </dev/null

  # Restore lockfile commits headlessly (and purge cache if --clean)
  ssh -T "${target_host}" "bash -s -- ${clean}" << 'REMOTE_NVIM_SYNC'
    export PATH="${HOME}/.local/bin:${PATH}"
    clean_mode="$1"
    if [[ "${clean_mode}" == "1" ]]; then
      # Not ~/.local/state/nvim: that is shada and undo, which restore cannot rebuild.
      echo "     ==> Purging remote plugin caches (~/.local/share/nvim/lazy, site, ~/.cache/nvim)..."
      rm -rf ~/.local/share/nvim/lazy ~/.local/share/nvim/site ~/.cache/nvim
    fi
    if command -v nvim >/dev/null 2>&1; then
      echo "     ==> Restoring Neovim plugins headlessly to match lockfile..."
      log="${TMPDIR:-/tmp}/dotfiles-nvim.log"
      if ! nvim --headless "+Lazy! restore" "+qa" </dev/null >"${log}" 2>&1; then
        echo "     Warning: remote nvim +Lazy! restore exited non-zero. Log on remote: ${log}" >&2
      fi
    fi
REMOTE_NVIM_SYNC
fi

# 3. Git configs
echo "  -> Git: .gitconfig, personal.conf, ignore"
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] scp config/git/config      -> ${target_host}:~/.gitconfig  (overwrites)"
  echo "     [dry-run] scp config/git/personal.conf -> ${target_host}:~/.config/git/personal.conf"
  echo "     [dry-run] scp config/git/ignore      -> ${target_host}:~/.config/git/ignore"
  echo "     [dry-run] generate                     ${target_host}:~/.config/git/local.conf (overwrites)"
else
  scp -q "${repo_dir}/config/git/config" "${target_host}:~/.gitconfig"
  scp -q "${repo_dir}/config/git/ignore" "${target_host}:~/.config/git/ignore"
  # Only under home: config/git/config also includes it via gitdir:~/code/daman/,
  # so shipping the file at all would apply the personal identity there.
  if [[ "${profile}" == "home" ]]; then
    scp -q "${repo_dir}/config/git/personal.conf" "${target_host}:~/.config/git/personal.conf"
  fi

  # Empty `helper =` drops osxkeychain; the identity include is profile-gated.
  ssh -T "${target_host}" "bash -s -- ${profile}" << 'REMOTE_GIT'
    remote_profile="$1"
    [ "$(uname -s)" = "Darwin" ] && exit 0
    mkdir -p ~/.config/git
    if [ "${remote_profile}" = "home" ]; then
      printf "[credential]\n\thelper =\n[include]\n\tpath = ~/.config/git/personal.conf\n" \
        > ~/.config/git/local.conf
    else
      printf "[credential]\n\thelper =\n" > ~/.config/git/local.conf
      rm -f ~/.config/git/personal.conf
    fi
REMOTE_GIT
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
  echo "     [dry-run] append PATH (~/.local/bin, ~/.local/share/fnm), EDITOR=nvim, TERM_PROGRAM=WezTerm and zsh_aliases sourcing to remote ~/.zshrc / ~/.bashrc"
else
  ssh -T "${target_host}" 'bash -s' << 'REMOTE_SCRIPT'
    # Script-owned sentinels: matching the payload caught foreign exports.
    ensure_line() {
      local rc="$1" marker="$2" block="$3"
      grep -qF "dotfiles-managed:${marker}" "${rc}" 2>/dev/null && return 0
      printf '\n# dotfiles-managed:%s\n%b' "${marker}" "${block}" >> "${rc}"
    }

    setup_rc() {
      local rc="$1"
      ensure_line "${rc}" path 'export PATH="$HOME/.local/bin:$HOME/.local/share/fnm:$PATH"\n'
      # herdr's edit_scrollback execs $EDITOR; unset, it falls back to vi.
      ensure_line "${rc}" editor 'export EDITOR="${EDITOR:-nvim}"\nexport VISUAL="${VISUAL:-$EDITOR}"\n'
      ensure_line "${rc}" term-program 'export TERM_PROGRAM="${TERM_PROGRAM:-WezTerm}"\n'
      ensure_line "${rc}" aliases '[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases\n'
    }

    if [[ -f ~/.zshrc || ! -f ~/.bashrc ]]; then
      touch ~/.zshrc
      setup_rc ~/.zshrc
    fi
    if [[ -f ~/.bashrc ]]; then
      setup_rc ~/.bashrc
    fi
REMOTE_SCRIPT
fi

# 6. Agent instructions
echo "  -> Agent: config/agent/AGENTS.md"
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] scp ${repo_dir}/config/agent/AGENTS.md ${target_host}:~/.claude/AGENTS.md"
  echo "     [dry-run] skipped instead if the remote path is already a symlink"
# A symlink means the remote has its own checkout and edits are live there; copying
# over it would silently freeze the file at this sync.
elif ssh -T "${target_host}" '[ -L ~/.claude/AGENTS.md ]' </dev/null; then
  echo "     remote symlinks it into a checkout, left alone"
else
  scp -q "${repo_dir}/config/agent/AGENTS.md" "${target_host}:~/.claude/AGENTS.md"
fi

# 7. Reload running Herdr server if present
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
