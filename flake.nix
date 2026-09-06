{
  description = "Daman's macOS development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-26.05-darwin";

    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";

    home-manager.url = "github:nix-community/home-manager/release-26.05";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";

    nix-homebrew.url = "github:zhaofengli/nix-homebrew";
  };

  outputs =
    {
      home-manager,
      nix-darwin,
      nix-homebrew,
      ...
    }:
    let
      # -----------------------------------------------------------------------
      # Single spot to explicitly configure username, hostname, or repo path.
      # Leave empty ("") to automatically fall back to the environment.
      # -----------------------------------------------------------------------
      manualUser = "";
      manualHost = "";
      manualDotfilesDir = "";
      # -----------------------------------------------------------------------

      envUser =
        let
          darwinUser = builtins.getEnv "DARWIN_USER";
          sudoUser = builtins.getEnv "SUDO_USER";
          normalUser = builtins.getEnv "USER";
        in
        if darwinUser != "" then
          darwinUser
        else if sudoUser != "" then
          sudoUser
        else if normalUser != "" && normalUser != "root" then
          normalUser
        else
          "";

      envHost =
        let
          darwinHost = builtins.getEnv "DARWIN_HOST";
          hostName = builtins.getEnv "HOSTNAME";
          host = builtins.getEnv "HOST";
        in
        if darwinHost != "" then
          darwinHost
        else if hostName != "" then
          hostName
        else if host != "" then
          host
        else
          "";

      envDotfiles = builtins.getEnv "DOTFILES_DIR";

      # Use manual override if set, otherwise fallback to env, otherwise fallback to "default" (for pure CI)
      username = if manualUser != "" then manualUser else if envUser != "" then envUser else "default";
      hostname = if manualHost != "" then manualHost else if envHost != "" then envHost else "default";
      system = "aarch64-darwin";
      homeDirectory = "/Users/${username}";
      dotfilesDirectory = if manualDotfilesDir != "" then manualDotfilesDir else if envDotfiles != "" then envDotfiles else "${homeDirectory}/code/daman/dotfiles";

      mkDarwinSystem = nix-darwin.lib.darwinSystem {
        specialArgs = {
          inherit
            dotfilesDirectory
            homeDirectory
            hostname
            system
            username
            ;
        };

        modules = [
          ./darwin.nix
          nix-homebrew.darwinModules.nix-homebrew
          {
            nix-homebrew = {
              enable = true;
              user = username;
              autoMigrate = true;
              mutableTaps = true;
              trust.taps = [ "sdkman/tap" ];
            };
          }
          home-manager.darwinModules.home-manager
          {
            home-manager.backupFileExtension = "before-home-manager";
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = {
              inherit dotfilesDirectory homeDirectory username;
            };
            home-manager.users.${username} = import ./home.nix;
          }
        ];
      };
    in
    {
      darwinConfigurations = {
        default = mkDarwinSystem;
      } // (if hostname != "" && hostname != "default" then {
        ${hostname} = mkDarwinSystem;
      } else {});
    };
}
