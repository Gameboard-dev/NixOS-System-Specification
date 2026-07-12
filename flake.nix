# This flake declares a complete NixOS system configuration.
# https://nixos.wiki/wiki/Flakes
#
# Testing and deployment:
#   sudo nixos-rebuild dry-run --flake .#nixos    # Preview changes
#   sudo nixos-rebuild switch --flake .#nixos     # Apply changes
#
# NixOS keeps older generations for rollback. Clean up with:
#   sudo nix-collect-garbage -d
#   sudo nix-collect-garbage --delete-older-than 30d
{
  description = "NixOS System Specification";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    # Each input below is a flake that pins its own copy of <package>.
    # 'follows' overrides that pin, forcing the input to use the same URL
    # as our definition for the flake (e.g. "home-manager")
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    plasma-manager = {
      url = "github:nix-community/plasma-manager/trunk";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, plasma-manager, sops-nix, ... }:
    let
      hostname = "nixos";
      username = "megatron";
      stateVersion = "26.05";
    in
    {
      nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit hostname username stateVersion; };

        modules = [
          ./configuration.nix
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit stateVersion username; };
            home-manager.sharedModules = [ plasma-manager.homeModules.plasma-manager ];
            home-manager.users.${username} = import ./home.nix;
          }
        ];
      };

      # Running `nix develop` in this directory drops you into a 
      # development shell where the secrets tools (age, sops)
      # are on PATH, without installing them system-wide.
      devShells =
        # Flakes require dev shells to be declared per architecture, 
        # specified in `hardware-configuration.nix`.
        let pkgs = self.nixosConfigurations.${hostname}.pkgs; in
        {
          ${pkgs.stdenv.hostPlatform.system}.default = pkgs.mkShell {
            buildInputs = with pkgs; [ age sops ];
          };
        };
    };
}
