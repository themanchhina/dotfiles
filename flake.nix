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
      # Empty ("") falls back to the environment; profile defaults to "work".
      # -----------------------------------------------------------------------
      manualUser = "";
      manualDotfilesDir = "";
      manualProfile = "";
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

      envDotfiles = builtins.getEnv "DOTFILES_DIR";
      envProfile = builtins.getEnv "DOTFILES_PROFILE";

      # Use manual override if set, otherwise fallback to env, otherwise fallback to "default" (for pure CI)
      username = if manualUser != "" then manualUser else if envUser != "" then envUser else "default";
      rawProfile = if manualProfile != "" then manualProfile else if envProfile != "" then envProfile else "work";
      profile =
        if builtins.elem rawProfile [ "work" "home" ] then
          rawProfile
        else
          throw "profile must be \"work\" or \"home\", got \"${rawProfile}\"";
      system = "aarch64-darwin";
      homeDirectory = "/Users/${username}";
      dotfilesDirectory = if manualDotfilesDir != "" then manualDotfilesDir else if envDotfiles != "" then envDotfiles else "${homeDirectory}/code/daman/dotfiles";

      mkDarwinSystem = nix-darwin.lib.darwinSystem {
        specialArgs = {
          inherit
            dotfilesDirectory
            homeDirectory
            profile
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
      darwinConfigurations.default = mkDarwinSystem;
    };
}
