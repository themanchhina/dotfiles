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
      username = "chhina";
      hostname = "chhina";
      system = "aarch64-darwin";
      homeDirectory = "/Users/${username}";
      dotfilesDirectory = "${homeDirectory}/code/daman/dotfiles";
    in
    {
      darwinConfigurations.${hostname} = nix-darwin.lib.darwinSystem {
        specialArgs = {
          inherit
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
    };
}
