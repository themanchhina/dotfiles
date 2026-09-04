{
  homeDirectory,
  hostname,
  lib,
  pkgs,
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
  } // (lib.optionalAttrs (hostname != "" && hostname != "default") {
    computerName = hostname;
    hostName = hostname;
  });

  homebrew = {
    enable = true;
    taps = [
      "sdkman/tap"
    ];
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
      "maven"
      "mysql"
      "nmap"
      "pnpm"
      "poppler"
      "qpdf"
      "redis"
      "sdkman/tap/sdkman-cli"
      "step"
      "uv"
      "watch"
      "whisper-cpp"
      "wireguard-tools"
      "yt-dlp"
      "zsh"
    ];
    casks = [
      "antigravity"
      "antigravity-cli"
      "battery"
      "cmux"
      "codex"
      "docker-desktop"
      "fluidvoice"
      "google-chrome"
      "google-drive"
      "openvpn-connect"
      "raycast"
      "slack"
      "tailscale-app"
      "wezterm"
      "windows-app"
      "zoom"
    ];
    onActivation = {
      autoUpdate = false;
      cleanup = "none";
      upgrade = false;
    };
  };

  system.defaults.NSGlobalDomain = {
    AppleInterfaceStyleSwitchesAutomatically = true;
    AppleShowAllExtensions = true;
    _HIHideMenuBar = true;
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
