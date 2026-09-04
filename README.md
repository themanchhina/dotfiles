# macOS dotfiles

This repository is the source of truth for Daman's Apple Silicon Mac setup. It uses Determinate Nix, nix-darwin, Home Manager, and nix-homebrew.

## New machine

The configuration currently expects:

- an Apple Silicon Mac
- the macOS account name `chhina`
- this repository at `~/code/daman/dotfiles`

Clone it, then run the bootstrap script:

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
flake.nix             inputs, host identity, and module wiring
darwin.nix            macOS defaults, networking, Homebrew, keyboard mapping
home.nix              user packages, shell, and managed file destinations
config/               application, Git, SSH, Neovim, and prompt configuration
scripts/bootstrap.sh  first activation on a new Mac
scripts/rebuild.sh    validate and apply the current configuration
scripts/update.sh     intentionally update Nix inputs and Homebrew packages
scripts/sync-brew.sh  audit and sync installed Homebrew packages with darwin.nix
legacy/               old Antigen, Brewfile, iTerm, Terminal, and setup files
```

Files in `legacy/` are retained only for reference and are not applied.

## Daily changes

Run this after changing any Nix-managed setting:

```sh
./scripts/rebuild.sh
```

Add software in one place:

- Nix command-line packages: `home.packages` in `home.nix`
- Homebrew taps, formulae, and casks: `homebrew` in `darwin.nix`

If you install packages ad-hoc via `brew install` or `brew install --cask`, run the sync script to audit unmanaged packages and keep `darwin.nix` up to date:

```sh
./scripts/sync-brew.sh
```

Homebrew upgrades are deliberately disabled during normal rebuilds so a settings change cannot unexpectedly update every application. To update the flake lock, Homebrew itself, formulae, and casks intentionally, run:

```sh
./scripts/update.sh
```

## Managed links

Home Manager declaratively manages all destination symlinks pointing to this repository (`mkOutOfStoreSymlink`).

This means:
- Edits to configuration files in `config/` (or via `~/.config/...`) apply immediately without requiring a Nix rebuild.
- Neovim plugins can update `lazy-lock.json` directly in the working tree.
- WezTerm configuration hot-reloads live on save.
- When bootstrapping a new machine, Home Manager creates all required symlinks automatically without manual `ln -s` commands.

## Host-specific notes

The DNS list is applied to the network services named in `darwin.nix`. Adapter names vary between Macs and docks. On a new machine, inspect them with:

```sh
networksetup -listallnetworkservices
```

Then update `networking.knownNetworkServices` before rebuilding if the Ethernet service uses a different name.

The machine and account names are centralized at the top of `flake.nix`. Supporting a second host should start with another `darwinConfigurations` entry rather than duplicating this repository.

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
