#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

usage() {
  cat << EOF
Usage: $(basename "$0") <ssh-host> [options]

Syncs essential configuration files to a remote machine over SSH:
  - Herdr: ~/.config/herdr/config.toml (theme, status symbols, 10MB scrollback, terminal notifications)
  - Neovim: ~/.config/nvim/ (init.lua, lazy-lock.json, plugins, keymaps)
  - Zsh: ~/.zsh_aliases (agent shortcuts gi/co/cc, docker wrappers, editor aliases)
  - Agent: ~/.claude/CLAUDE.md (standing coding-agent instructions; skipped when the
           remote already symlinks it into a checkout, so live edits keep working)
  - Shell: sets PATH (~/.local/bin), EDITOR=nvim, TERM_PROGRAM=WezTerm & sources
           aliases in remote ~/.zshrc / ~/.bashrc
  - Herdr Server: automatically reloads herdr server config on the remote machine

Arguments:
  <ssh-host>           SSH host name (e.g. 'india', 'home', or 'user@host.com')

Options:
  -t, --install-tools, --tools
                       Install missing CLI tools (nvim, herdr, rg, fd, lazygit, jq, fzf, direnv, uv, fnm, tree-sitter) into ~/.local/bin
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
[[ -n "${target_host}" && "${target_host}" != -* && "${target_host}" != *[[:space:]]* ]] || {
  echo "Error: Invalid SSH host: '${target_host}'." >&2
  exit 1
}

install_tools=0
dry_run=0
clean=0
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

herdr_version=""
if [[ ${install_tools} -eq 1 && ${dry_run} -eq 0 ]]; then
  herdr_version="$(herdr --version </dev/null 2>/dev/null | awk 'NR == 1 { print $2 }' || true)"
  [[ "${herdr_version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+([.-][A-Za-z0-9.]+)?$ ]] || {
    echo "Error: Local Herdr returned an invalid version: '${herdr_version}'." >&2
    exit 1
  }
fi

if [[ ${dry_run} -eq 0 ]]; then
  echo "==> Testing SSH connection to '${target_host}'..."
  if ! ssh -q -T -o BatchMode=yes -o ConnectTimeout=8 "${target_host}" exit 2>/dev/null; then
    if ! ssh -T -o ConnectTimeout=8 "${target_host}" exit; then
      echo "Error: Could not connect to '${target_host}' over SSH." >&2
      exit 1
    fi
  fi
fi

echo "==> Preparing remote directories on '${target_host}'..."
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] remote: rm -f ~/.oh-my-bash/log/update.lock"
  echo "     [dry-run] remote: mkdir -p ~/.config/herdr ~/.config/nvim ~/.local/bin ~/.local/share ~/.claude"
else
  ssh -T "${target_host}" '
    set -eu
    rm -f ~/.oh-my-bash/log/update.lock 2>/dev/null || true
    mkdir -p ~/.config/herdr ~/.config/nvim ~/.local/bin ~/.local/share ~/.claude
  ' </dev/null
fi

if [[ ${install_tools} -eq 1 ]]; then
  echo "==> Checking and installing essential CLI tools on '${target_host}'..."
  # Fed on stdin, never scp'd: a predictable remote ~/.remote-tools-$$.sh can be a pre-planted symlink.
  if [[ ${dry_run} -eq 1 ]]; then
    echo "     [dry-run] ssh -T ${target_host} 'bash -s' < ${repo_dir}/scripts/lib/remote-tools.sh"
  else
    ssh -T "${target_host}" "bash -s -- '${herdr_version}'" < "${repo_dir}/scripts/lib/remote-tools.sh"
  fi
fi

if [[ ${dry_run} -eq 0 ]] && ! ssh -T "${target_host}" 'export PATH="$HOME/.local/bin:$PATH"; nvim --version | grep -q "^NVIM v" && nvim --headless --clean -i NONE -n -c '\''lua if vim.fn.has("nvim-0.11.2") ~= 1 or not jit or vim.v.errmsg ~= "" then vim.cmd("cquit") end'\'' -c qa' </dev/null; then
  echo "Error: Remote Neovim needs >= 0.11.2, LuaJIT and a working stock runtime. Re-run with --install-tools." >&2
  exit 1
fi

if [[ ${dry_run} -eq 0 ]]; then
  ssh -T "${target_host}" '
    export PATH="$HOME/.local/bin:$PATH"
    if command -v fzf >/dev/null 2>&1 && ! fzf --bash </dev/null >/dev/null 2>&1; then
      echo "Error: Remote fzf needs native shell integration (>= 0.48). Re-run with --install-tools." >&2
      exit 1
    fi
  ' </dev/null
fi

echo "==> Syncing configs to '${target_host}'..."

echo "  -> Herdr: config/herdr/config.toml"
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] scp ${repo_dir}/config/herdr/config.toml ${target_host}:~/.config/herdr/config.toml.tmp, then rename to config.toml"
else
  scp -q "${repo_dir}/config/herdr/config.toml" "${target_host}:~/.config/herdr/config.toml.tmp"
  ssh -T "${target_host}" 'mv -f ~/.config/herdr/config.toml.tmp ~/.config/herdr/config.toml' </dev/null
fi

echo "  -> Neovim: config/nvim/"
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] remote: rm -rf ~/.config/nvim.tmp"
  echo "     [dry-run] scp -r ${repo_dir}/config/nvim ${target_host}:~/.config/nvim.tmp"
  echo "     [dry-run] remote: rm -rf ~/.config/nvim   <-- DELETES the remote config, no backup"
  echo "     [dry-run] remote: mv ~/.config/nvim.tmp ~/.config/nvim"
  if [[ ${clean} -eq 1 ]]; then
    echo "     [dry-run] remote: rm -rf ~/.local/share/nvim/lazy ~/.local/share/nvim/site ~/.cache/nvim"
  fi
else
  ssh -T "${target_host}" "rm -rf ~/.config/nvim.tmp" </dev/null
  scp -q -r "${repo_dir}/config/nvim" "${target_host}:~/.config/nvim.tmp"
  ssh -T "${target_host}" "rm -rf ~/.config/nvim && mv ~/.config/nvim.tmp ~/.config/nvim" </dev/null

fi

echo "  -> Zsh: .zsh_aliases"
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] scp ${repo_dir}/config/zsh/zsh_aliases ${target_host}:~/.zsh_aliases"
else
  ssh -T "${target_host}" '[ ! -f ~/.zsh_aliases ] || [ -e ~/.zsh_aliases.bak ] || cp -p ~/.zsh_aliases ~/.zsh_aliases.bak' </dev/null
  scp -q "${repo_dir}/config/zsh/zsh_aliases" "${target_host}:~/.zsh_aliases"
fi

echo "  -> Ensuring remote shell environment (PATH, TERM_PROGRAM=WezTerm & alias sourcing)..."
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] back up and configure ~/.zshenv (PATH, editor, terminal, fzf commands) and ~/.zshrc / ~/.bashrc (aliases, fnm, fzf shortcuts, direnv)"
else
  ssh -T "${target_host}" 'bash -s' << 'REMOTE_SCRIPT'
    set -euo pipefail
    # Match our markers, not similar exports already owned by the host.
    ensure_line() {
      local rc="$1" marker="$2" block="$3"
      grep -qF "dotfiles-managed:${marker}" "${rc}" 2>/dev/null && return 0
      printf '\n# dotfiles-managed:%s\n%b' "${marker}" "${block}" >> "${rc}"
    }

    backup_once() {
      local file="$1"
      [[ ! -s "${file}" || -e "${file}.bak" ]] || cp -p "${file}" "${file}.bak"
    }

    # .zshenv, not .zshrc: herdr spawns popups and $EDITOR non-interactively.
    setup_env() {
      local file="$1"
      backup_once "${file}"
      # Per entry, and guarded: .zshenv also runs for nested shells.
      ensure_line "${file}" path 'for dir in "$HOME/.local/bin" "$HOME/.local/share/fnm"; do
  [ -d "$dir" ] || continue
  case ":$PATH:" in
    *":$dir:"*) ;;
    *) PATH="$dir:$PATH" ;;
  esac
done
export PATH
unset dir
'
      # herdr's edit_scrollback execs $EDITOR; unset, it falls back to vi.
      ensure_line "${file}" editor-v2 'export EDITOR=nvim\nexport VISUAL=nvim\n'
      ensure_line "${file}" term-program 'export TERM_PROGRAM="${TERM_PROGRAM:-WezTerm}"\n'
      ensure_line "${file}" fzf-commands 'export FZF_DEFAULT_COMMAND="fd --type f --strip-cwd-prefix --hidden --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type d --strip-cwd-prefix --hidden --exclude .git"
'
    }

    setup_rc() {
      local rc="$1"
      backup_once "${rc}"
      # Bash has no .zshenv equivalent, so its environment stays in .bashrc.
      if [[ "${rc}" == *.bashrc ]]; then setup_env "${rc}"; fi
      ensure_line "${rc}" aliases '[[ -f ~/.zsh_aliases ]] && source ~/.zsh_aliases\n'
      case "${rc}" in
        *.zshrc)
          ensure_line "${rc}" fnm 'command -v fnm >/dev/null 2>&1 && eval "$(fnm env --use-on-cd --shell zsh)"\n'
          ensure_line "${rc}" shell-tools 'if [[ $- == *i* ]]; then
  command -v fzf >/dev/null 2>&1 && eval "$(fzf --zsh)"
  command -v direnv >/dev/null 2>&1 && eval "$(direnv hook zsh)"
fi
'
          ;;
        *.bashrc)
          ensure_line "${rc}" fnm 'command -v fnm >/dev/null 2>&1 && eval "$(fnm env --use-on-cd --shell bash)"\n'
          ensure_line "${rc}" shell-tools 'if [[ $- == *i* ]]; then
  command -v fzf >/dev/null 2>&1 && eval "$(fzf --bash)"
  command -v direnv >/dev/null 2>&1 && eval "$(direnv hook bash)"
fi
'
          ;;
      esac
    }

    setup_env ~/.zshenv
    setup_rc ~/.zshrc
    setup_rc ~/.bashrc
REMOTE_SCRIPT
fi

# Shell/runtime setup must precede plugin restoration so Mason and plugin hooks see it.
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] remote: nvim --headless '+lua require(\"config.sync\")(\"restore\")' '+cquit 1'"
else
  ssh -T "${target_host}" "bash -s -- ${clean}" << 'REMOTE_NVIM_SYNC'
    set -euo pipefail
    export PATH="${HOME}/.local/bin:${HOME}/.local/share/fnm:${PATH}"
    if command -v fnm >/dev/null 2>&1; then
      eval "$(fnm env --shell bash </dev/null)"
    fi
    if [[ "$1" == "1" ]]; then
      rm -rf ~/.local/share/nvim/lazy ~/.local/share/nvim/site ~/.cache/nvim
    fi
    log="$(mktemp "${TMPDIR:-/tmp}/dotfiles-nvim.XXXXXX")"
    # config.sync exits itself; cquit catches load errors before it takes control.
    if nvim --headless '+lua require("config.sync")("restore")' '+cquit 1' </dev/null >"${log}" 2>&1; then
      rm -f "${log}"
    else
      echo "Error: Remote Neovim plugin restore failed. Log: ${log}" >&2
      exit 1
    fi
REMOTE_NVIM_SYNC
fi

echo "  -> Agent: config/agent/AGENTS.md"
if [[ ${dry_run} -eq 1 ]]; then
  echo "     [dry-run] scp ${repo_dir}/config/agent/AGENTS.md ${target_host}:~/.claude/CLAUDE.md.tmp, then rename to CLAUDE.md"
  echo "     [dry-run] skipped instead if the remote path is already a symlink"
# Preserve remote checkout links so their edits remain live.
elif ssh -T "${target_host}" '[ -L ~/.claude/CLAUDE.md ]' </dev/null; then
  echo "     remote symlinks it into a checkout, left alone"
else
  scp -q "${repo_dir}/config/agent/AGENTS.md" "${target_host}:~/.claude/CLAUDE.md.tmp"
  ssh -T "${target_host}" 'mv -f ~/.claude/CLAUDE.md.tmp ~/.claude/CLAUDE.md' </dev/null
fi

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
