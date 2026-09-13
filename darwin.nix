{
  homeDirectory,
  lib,
  pkgs,
  profile,
  system,
  username,
  ...
}:

{
  # Determinate Nix manages the daemon.
  nix.enable = false;

  nixpkgs.hostPlatform = system;
  nixpkgs.config.allowUnfree = true;

  # Required so nix-darwin manages /etc/zshrc and properly sets up PATH
  programs.zsh.enable = true;

  # Declaratively remap Caps Lock to Escape
  system.keyboard = {
    enableKeyMapping = true;
    remapCapsLockToEscape = true;
  };

  # Enable Touch ID for sudo authentication (including Apple Watch)
  security.pam.services.sudo_local.touchIdAuth = true;

  # System fonts installed to /Library/Fonts/Nix Fonts
  fonts.packages = [
    pkgs.meslo-lgs-nf
  ];

  system.primaryUser = username;
  users.users.${username}.home = homeDirectory;
  system.stateVersion = 6;

  networking = {
    dns = [ "1.1.1.1" "1.0.0.1" ];
    knownNetworkServices = [
      "Wi-Fi"
      "AX88179A"
      "AX88179B"
      "USB 10/100/1000 LAN"
      "Thunderbolt Bridge"
    ];
  };

  homebrew = {
    enable = true;
    taps = [
      "sdkman/tap"
    ];
    masApps = lib.optionalAttrs (profile == "home") {
      "Irvue" = 1039633667;
    };
    # Personal VPN, sync and scanning tools are gated behind the "home" profile.
    brews = [
      "awscli"
      "azure-cli"
      "circleci"
      "docker-compose"
      "ffmpeg"
      "fnm"
      "gh"
      "git"
      "go"
      "gradle"
      "herdr"
      "kubernetes-cli"
      "mas"
      "maven"
      "mysql"
      "pnpm"
      "poppler"
      "qpdf"
      "redis"
      "sdkman/tap/sdkman-cli"
      "step"
      "uv"
      "watch"
      "whisper-cpp"
      "zsh"
    ] ++ lib.optionals (profile == "home") [
      "nmap"
      "wireguard-tools"
      "yt-dlp"
    ];
    casks = [
      "antigravity"
      "antigravity-cli"
      "battery"
      "codex"
      "docker-desktop"
      "fluidvoice"
      "google-chrome"
      "raycast"
      "slack"
      "visual-studio-code"
      "wezterm"
    ] ++ lib.optionals (profile == "home") [
      "google-drive"
      "openvpn-connect"
      "tailscale-app"
      "windows-app"
      "zoom"
    ];
    onActivation = {
      autoUpdate = false;
      cleanup = "none";
      upgrade = false;
    };
  };

  # Fixes `compinit:527: no such file or directory: .../site-functions/_brew`.
  # The `../..` resolves through the symlink into the store, so require -L.
  # postActivation: extraActivation runs before nix-homebrew creates the prefix.
  system.activationScripts.postActivation.text = ''
    if [ -L /opt/homebrew/Library/Homebrew ]; then
      if [ ! -e /opt/homebrew/completions ] || [ -L /opt/homebrew/completions ]; then
        ln -sfn /opt/homebrew/Library/Homebrew/../../completions /opt/homebrew/completions
      fi
    fi
  '';

  system.defaults.NSGlobalDomain = {
    AppleInterfaceStyleSwitchesAutomatically = true;
    AppleShowAllExtensions = true;
    "com.apple.swipescrolldirection" = false;
  };
  system.defaults.dock = {
    autohide = true;
    show-recents = false;
    tilesize = 58;
  };
  system.defaults.finder = {
    FXPreferredViewStyle = "Nlsv";
    FXRemoveOldTrashItems = true;
    ShowPathbar = true;
    ShowStatusBar = true;
  };
  system.defaults.CustomUserPreferences = {
    "com.apple.desktopservices" = {
      DSDontWriteNetworkStores = true;
      DSDontWriteUSBStores = true;
    };
  };
  system.defaults.WindowManager = {
    EnableTiledWindowMargins = false;
    EnableTopTilingByEdgeDrag = false;
  };
  system.defaults.controlcenter.BatteryShowPercentage = true;
  system.defaults.menuExtraClock = {
    ShowAMPM = true;
    ShowDate = 0;
    ShowDayOfWeek = true;
  };
  system.defaults.trackpad.TrackpadRightClick = true;
}
