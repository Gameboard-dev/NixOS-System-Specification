# Nix flakes provide reproducible Nix expressions whose dependencies are pinned
# in the committed flake.lock. This flake declares a complete NixOS system
# configuration that can be tested and applied using nixos-rebuild.
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
    flake-utils.url = "github:numtide/flake-utils";
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      #  Ensure flake inputs use the same nixpkgs to avoid dependency conflicts.
      inputs.nixpkgs.follows = "nixpkgs";
    };
    plasma-manager = {
      url = "github:nix-community/plasma-manager/trunk";
      # Ensure flake inputs use the same nixpkgs and home-manager versions to avoid dependency conflicts.
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
      hardwareConfig = import ./hardware-configuration.nix;
      system = hardwareConfig.nixpkgs.hostPlatform;
      pkgs = nixpkgs.legacyPackages.${system};
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
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [ age sops ];
      };
    };
}
