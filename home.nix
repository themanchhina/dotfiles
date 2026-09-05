{
  config,
  dotfilesDirectory,
  homeDirectory,
  lib,
  pkgs,
  username,
  ...
}:

  let
    link = path: config.lib.file.mkOutOfStoreSymlink "${dotfilesDirectory}/${path}";
  in
  {
    home.username = username;
    home.homeDirectory = homeDirectory;
    home.stateVersion = "24.11";
    home.packages = with pkgs; [
      fd
      fzf
      jq
      lazygit
      neovim
      ripgrep
    ];
    home.sessionVariables = {
      EDITOR = "nvim";
      VISUAL = "nvim";
      DOTFILES_DIR = dotfilesDirectory;
    };

    xdg.configFile."git/personal.conf".source = link "config/git/personal.conf";
    xdg.configFile."git/ignore".source = link "config/git/ignore";
    xdg.configFile."herdr/config.toml".source = link "config/herdr/config.toml";
    xdg.configFile."wezterm/wezterm.lua".source = link "config/wezterm/wezterm.lua";
    xdg.configFile."nvim".source = link "config/nvim";

    home.file.".gitconfig".source = link "config/git/config";
    home.file.".ssh/config".source = link "config/ssh/config";
    home.file.".p10k.zsh".source = link "config/zsh/p10k.zsh";
    home.file.".zsh_aliases".source = link "config/zsh/zsh_aliases";

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultCommand = "fd --type f --strip-cwd-prefix --hidden --exclude .git";
    fileWidgetCommand = "fd --type f --strip-cwd-prefix --hidden --exclude .git";
    changeDirWidgetCommand = "fd --type d --strip-cwd-prefix --hidden --exclude .git";
  };

  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      plugins = [
        "git"
        "command-not-found"
        "docker"
        "docker-compose"
      ];
    };

    plugins = [
      {
        name = "powerlevel10k";
        src = pkgs.zsh-powerlevel10k;
        file = "share/zsh-powerlevel10k/powerlevel10k.zsh-theme";
      }
    ];

    initContent = lib.mkMerge [
      (lib.mkOrder 500 ''
        if [[ -r "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh" ]]; then
          source "''${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-''${(%):-%n}.zsh"
        fi
      '')
      (lib.mkOrder 550 ''
        fpath+=("${pkgs.zsh-completions}/share/zsh/site-functions")
      '')
      (lib.mkOrder 1000 ''
        [[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
        [[ ! -f ~/.zsh_aliases ]] || source ~/.zsh_aliases

        local brew_prefix="/opt/homebrew"
        [[ -d "$brew_prefix" ]] || brew_prefix="/usr/local"
        if [[ -d "$brew_prefix/opt/sdkman-cli/libexec" ]]; then
          export SDKMAN_DIR="$brew_prefix/opt/sdkman-cli/libexec"
          [[ -s "$SDKMAN_DIR/bin/sdkman-init.sh" ]] && source "$SDKMAN_DIR/bin/sdkman-init.sh"
          [[ -d "$SDKMAN_DIR/candidates/java/current" ]] && export JAVA_HOME="$SDKMAN_DIR/candidates/java/current"
        fi

        [[ -x /opt/homebrew/bin/fnm ]] && eval "$(/opt/homebrew/bin/fnm env --use-on-cd)"
      '')
    ];

    profileExtra = ''
      export HOST="''${HOST:-$(scutil --get LocalHostName 2>/dev/null || hostname -s)}"
      [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
    '';
  };
}
