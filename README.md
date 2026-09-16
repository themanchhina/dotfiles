# macOS dotfiles

This repository is the source of truth for Daman's Apple Silicon Mac setup. It uses Determinate Nix, nix-darwin, Home Manager, and nix-homebrew. It also pushes the terminal and editor configuration to remote Linux hosts over SSH, via `scripts/sync-remote.sh`.

## New machine

The configuration requires:

- an Apple Silicon Mac
- the macOS account name and repository directory (automatically inferred from your environment, or customizable in `flake.nix`)

Clone it into your preferred directory, then run the bootstrap script:

```sh
mkdir -p ~/code/daman
git clone https://github.com/themanchhina/dotfiles.git ~/code/daman/dotfiles
cd ~/code/daman/dotfiles
./scripts/bootstrap.sh
```

If Determinate Nix is missing, the script asks before installing it with the official installer. The first activation installs nix-darwin and Homebrew; later activations use the installed `darwin-rebuild`.

Home Manager backs up conflicting files with the suffix `.before-home-manager`. It never deletes an existing configuration silently. SSH private keys are intentionally not stored here and must be restored separately.

## Repository layout

```text
flake.nix              inputs, user identity, and module wiring
darwin.nix             macOS defaults, networking, Homebrew, keyboard mapping
home.nix               user packages, shell, and managed file destinations
config/                application, Git, SSH, Neovim, and prompt configuration
scripts/bootstrap.sh   first activation on a new Mac
scripts/rebuild.sh     validate and apply the current configuration
scripts/update.sh      intentionally update Nix inputs and Homebrew packages
scripts/sync-brew.sh   audit installed Homebrew packages against darwin.nix (read-only)
scripts/sync-remote.sh push terminal and editor config to a remote Linux host
scripts/remote-files.sh transfer Finder clipboard files or explicit paths over SCP
scripts/remote-preview.sh open remote Neovim Markdown previews in the Mac browser
scripts/lib/           shared shell helpers, and the remote tool installer
.github/workflows/     CI: evaluates both profiles, lints the shell scripts
```

## Daily changes

Run this after changing any Nix-managed setting:

```sh
./scripts/rebuild.sh
```

Add software in one place:

- Nix command-line packages: `home.packages` in `home.nix`
- Homebrew taps, formulae, and casks: `homebrew` in `darwin.nix`

If you install packages ad-hoc via `brew install` or `brew install --cask`, run the audit. It only reports drift, in both directions; you edit `darwin.nix` yourself:

```sh
./scripts/sync-brew.sh
```

Homebrew upgrades are deliberately disabled during normal rebuilds so a settings change cannot unexpectedly update every application. To update the flake lock, Homebrew itself, formulae, and casks intentionally, run:

```sh
./scripts/update.sh
```

The two scripts treat Neovim plugins oppositely, which is the point: `rebuild.sh` restores them to `config/nvim/lazy-lock.json`, while `update.sh` advances them and rewrites that lockfile in the working tree. Expect `update.sh` to leave the repo dirty.

Both accept `--clean`, which purges `~/.local/share/nvim/{lazy,site}` and `~/.cache/nvim` before restoring. It deliberately leaves `~/.local/state/nvim` alone, since shada and undo history cannot be rebuilt from a lockfile.

## Profiles

Software that is fine personally but a policy problem on a work machine is gated behind a profile. `work` is the default, so an unset value can never install personal VPN or sync tooling.

```sh
./scripts/rebuild.sh --profile home    # adds the personal set
./scripts/rebuild.sh                   # work: the shared set only
```

Set `manualProfile = "home"` at the top of `flake.nix` to make it permanent for a machine. Note it takes precedence, so `--profile work` then becomes a silent no-op; leave it empty if you want the flag to decide. `home` adds the casks `google-drive`, `openvpn-connect`, `tailscale-app`, `windows-app` and `zoom`; the formulae `nmap`, `wireguard-tools` and `yt-dlp`; and the Mac App Store app `Irvue`.

Profiles apply to Mac packages. Remote Git identities, credential helpers and configuration belong to each host; `sync-remote.sh` does not modify them and no longer takes `--profile`.

**Switching profile does not uninstall anything.** `homebrew.onActivation.cleanup` is `"none"`, so dropping a package from the list stops it being managed but leaves it on disk. To actually remove the personal set from a machine:

```sh
brew uninstall --cask google-drive openvpn-connect tailscale-app windows-app zoom
brew uninstall nmap wireguard-tools yt-dlp
mas uninstall 1039633667   # Irvue
```

## Managed links

Every managed destination is declared in `home.nix` and symlinked with `mkOutOfStoreSymlink`. `config/raycast/` is deliberately not managed, since it is imported interactively. CI asserts that every declared link source exists.

This means:
- Edits to configuration files in `config/` (or via `~/.config/...`) apply immediately without requiring a Nix rebuild.
- Neovim plugins can update `lazy-lock.json` directly in the working tree.
- WezTerm configuration hot-reloads live on save.
- When bootstrapping a new machine, Home Manager creates all required symlinks automatically without manual `ln -s` commands.

## Remote hosts

`scripts/sync-remote.sh` pushes terminal, editor and coding-agent configuration to a remote Linux box over SSH. Tool configuration is replaced outright; do not keep remote-only Neovim changes there. Existing shell profiles and aliases get a `.bak` copy before their first modification. Repeated syncs retain that original backup. Git configuration is left alone.

```sh
./scripts/sync-remote.sh india                          # sync configs only
./scripts/sync-remote.sh india --install-tools          # also install CLI tools into ~/.local/bin (-t)
./scripts/sync-remote.sh india --dry-run                # print what would change
herdr --remote india                                   # attach from the Mac
```

It initializes both Bash and Zsh (creating missing rc files), including PATH, fnm, `EDITOR`/`VISUAL`, terminal identity, fzf shortcuts (Ctrl+R, Ctrl+T, Alt+C), and direnv hooks. fzf uses the same fd searches as the Mac; prompts and development stacks remain host-owned. Herdr configuration and agent instructions are staged before replacement so interrupted uploads leave the live files intact. The sync reloads a running Herdr server. Open a new shell after syncing. `--dry-run` does not connect. Neovim plugin failures make the command fail and retain a diagnostic log, including failures where Lazy would otherwise return a successful process exit.

`--install-tools` requires Linux x86_64/ARM64 with Git, curl, tar, gzip, unzip, sha256sum, and a C compiler. On bare Ubuntu, install missing prerequisites with `sudo apt-get install build-essential unzip git curl`. It installs the existing CLI set (Neovim, Herdr, ripgrep, fd, lazygit, jq, fzf, direnv, uv, fnm, tree-sitter) in your home directory. fzf is upgraded when it lacks native shell integration (requires 0.48 or newer). Herdr's version matches the initiating Mac, and its downloaded binary is checksum-verified. Neovim must be at least 0.11.2 with LuaJIT. If tree-sitter's binary cannot run on the host, it builds locally using Cargo or a temporary Rust toolchain, removed afterward.

Neovim's distribution lives separately in `~/.local/opt/nvim`, with `~/.local/bin/nvim` linked to it. Reinstalling replaces the runtime completely while retaining user/plugin data in `~/.local/share/nvim`, avoiding stale runtime files after a version change.

Development stacks and agents remain the host's responsibility. fnm initialization uses an existing/default Node installation; on a bare host, `fnm install --lts` provides Node for Node-based editor tools. `--clean` (or `-c`) additionally purges Neovim plugin caches. The sync also removes a stale `~/.oh-my-bash/log/update.lock` and installs shared agent instructions as `~/.claude/CLAUDE.md`.

## Clipboard and remote files

Run `herdr --remote india` on the Mac for native text/image integration. Cmd+C copies selected text, Cmd+V pastes Mac text into the remote pane, and Neovim yanks copy out through OSC 52. Remote Neovim's `p` uses its cached register when no system clipboard is available; use Cmd+V for newly copied Mac text. Cmd+Shift+V invokes Herdr's image upload and inserts a remote image path.

For arbitrary files/folders, use `remote-files` on the Mac. Omit local paths to upload the files copied in Finder with Cmd+C:

```sh
remote-files put india /tmp                         # files copied in Finder
remote-files put india "~/uploads" ./report.pdf "./folder with spaces"
remote-files get india /srv/project/report.pdf ~/Downloads
remote-files get india /srv/project/results ~/Downloads
```

The destination directory must exist. SCP can overwrite same-named files. Quote remote `~` paths to prevent expansion on the Mac. Use an SSH alias or `user@hostname`; use an alias for IPv6 addresses.

## Remote Markdown browser preview

Start the bridge in a second **Mac** terminal:

```sh
remote-preview india
```

Press **Space c p** in a Markdown buffer in remote Neovim. The bridge forwards its loopback-only preview server over SSH and opens the exact preview page in the Mac browser. Keep it running; Ctrl+C stops the bridge. It also picks up a preview already started. If a saved URL is stale, toggle the preview again.

Each host supports one preview server on port 8765 at a time. To preview a second host concurrently, choose another Mac port: `remote-preview home 8766`. Mac-local Neovim previews keep their normal browser behavior.

## Keybindings

Herdr's terminal fallback is **Ctrl+B**, followed by the listed key; Neovim's leader is **Space**. Herdr-specific Cmd shortcuts target a foreground Herdr client and are ignored in ordinary SSH/mosh sessions.

| Action | Mac shortcut | Terminal fallback |
| --- | --- | --- |
| Open a link / select through mouse capture | Cmd+click / Shift+drag | Herdr Ctrl+click / terminal selection |
| Copy / paste text | Cmd+C / Cmd+V | Neovim yank / paste registers |
| Paste a remote image | Cmd+Shift+V | Ctrl+Alt+V in Herdr remote |
| Previous / next Herdr pane | Cmd+Shift+J / K | Prefix j / k |
| Directional Herdr pane focus | Ctrl+Alt+H/J/K/L | Left / down / up / right |
| Directional Neovim split focus | Ctrl+H/J/K/L | Left / down / up / right |
| Vertical / horizontal Herdr split | Cmd+Shift+D / S | Prefix v / - |
| Vertical / horizontal Neovim split | — | Space v / - |
| Previous / next Herdr tab | Cmd+Shift+U / I | Prefix p / n |
| New tab / close pane | Cmd+Shift+T / W | Prefix c / x |
| Zoom / scrollback / Lazygit | Cmd+Shift+Z / E / L | Prefix z / e / l |
| Herdr settings / help | — | Prefix s / ? |
| Markdown browser preview | — | Space c p |

Plain Ctrl+V remains Neovim visual-block selection. Option+J/K remains available for LazyVim's move-line shortcuts. Workspace and rename shortcuts retain the Cmd+Option bindings in `wezterm.lua`.

## Browsing remote files in VS Code

VS Code runs on the Mac and reaches the remotes with the `Kelvin.vscode-sshfs` extension, which mounts a remote directory as a workspace folder over SFTP. Nothing is installed on the remote and no port is opened, so it works on hosts whose glibc is too old for VS Code Remote-SSH or code-server. `Cmd+K V` gives a side-by-side markdown preview with synchronized scrolling, and mermaid diagrams render natively since VS Code 1.121.

The cask and the extension are declared, and `settings.json` is symlinked from `config/vscode/settings.json` so the settings UI stays writable.

The tracked `settings.json` starts empty; VS Code owns it and its edits get versioned. `sshfs.configpaths` is left unset because it must be an **absolute** path and so differs per machine: set it once per Mac via the settings UI, to the path activation prints. Host definitions stay out of this repo because it is public and the SSH FS UI writes a password into a host config if you enter one. Each file there is a JSON array, comments allowed:

```jsonc
// ~/.config/vscode-sshfs/india.json
[
  { "name": "india", "host": "india.damanchhina.com", "username": "daman", "root": "/home/daman" }
]
```

`sshfs.configpaths` must be an absolute path; a relative one or a `~` is silently ignored, so activation warns if it does not match `$HOME`. Note the extension does not read `~/.ssh/config`, so host, user and key are repeated here.

## Git identity

The personal identity applies only inside `~/code/daman/`, and `user.useConfigOnly` is set. A repository outside that root has no identity, so rather than silently attributing a commit to the personal address, git refuses.

That refusal is not always graceful. `commit`, `commit --amend`, `merge --no-ff` and `tag -a` fail cleanly, but anything that commits mid-operation leaves state behind: `rebase` stops at a detached HEAD with a `.git/rebase-merge`, and `revert` and `cherry-pick` leave a dirty index. Recover with the matching `--abort`. Because `pull.rebase` is true a plain `git pull` on a diverged branch hits the rebase path, and because `rebase.autoStash` is also true it will have stashed your uncommitted work first: `git rebase --abort` restores it, but `--skip` or `--continue` will not, and `git stash list` does not show it.

So set an identity before working in a new root. `useConfigOnly` requires **both** values, so per repository that is `git config user.email ...` and `git config user.name ...`; otherwise add another `includeIf` in `config/git/config`.

## Host-specific notes

The DNS list is applied to the network services named in `darwin.nix`. Adapter names vary between Macs and docks. On a new machine, inspect them with:

```sh
networksetup -listallnetworkservices
```

Then update `networking.knownNetworkServices` before rebuilding if the Ethernet service uses a different name.

The account name and repository directory are centralized at the top of `flake.nix`. There is a single `darwinConfigurations.default`; supporting a second machine should start with another entry there rather than duplicating this repository.

## New machine checklist (Day 1)

### 1. Pre-bootstrap (Secrets)
Private keys and sensitive credentials are intentionally not committed to Git. Restore your SSH keys before running the bootstrap script:

```sh
mkdir -p ~/.ssh && chmod 700 ~/.ssh
# Copy over your private keys: daman, bluecrew, amarpreet, aamir
chmod 600 ~/.ssh/*
```

### 2. Bootstrap
Clone the repo and execute the bootstrap script:

```sh
mkdir -p ~/code/daman
git clone https://github.com/themanchhina/dotfiles.git ~/code/daman/dotfiles
cd ~/code/daman/dotfiles
./scripts/bootstrap.sh
```

### 3. Post-bootstrap (Authentication & Permissions)
- **Authenticate developer CLIs**:
  ```sh
  gh auth login
  aws configure
  az login
  ```
- **macOS Permissions**: Open **System Settings → Privacy & Security** and grant Accessibility / Input Monitoring permissions as needed for **Raycast**, **WezTerm**, and **Docker Desktop**.
- **Restore Raycast Settings**: If you exported a `.rayconfig` file, restore it with `open ~/code/daman/dotfiles/config/raycast/settings.rayconfig` (or sign into your Raycast account for Cloud Sync).
- **1Password / Password Manager**: Sign in to your password manager and enable SSH agent integration if applicable.
