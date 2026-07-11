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
    # nixpkgs provides the set of packages and NixOS module definitions for the specified
    # NixOS release. Dependencies should track the same version using 'inputs.nixpkgs.follows'
    # to avoid conflicts with package dependencies.
    # https://nixos-and-flakes.thiscute.world/other-usage-of-flakes/inputs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";

    flake-utils.url = "github:numtide/flake-utils";
    
    # home-manager provides declarative user-level configuration management.
    # https://github.com/nix-community/home-manager
    home-manager = {
      url = "github:nix-community/home-manager/release-26.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    
    # plasma-manager extends home-manager with KDE Plasma (desktop) configuration options.
    # https://github.com/nix-community/plasma-manager
    plasma-manager = {
      url = "github:nix-community/plasma-manager/trunk";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };

    # Add sops-nix for encrypted secrets management
    # https://github.com/mic92/sops-nix#how-it-works
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, home-manager, plasma-manager, sops-nix, ... }:
    let
      # Hostname for network identification.
      hostname = "nixos";
      # Username for login.
      username = "megatron";
      # stateVersion pins the NixOS release this machine was first installed with.
      # Do not change this value when upgrading NixOS; it ensures compatibility of
      # on-disk data formats and must remain frozen for the lifetime of the system.
      stateVersion = "26.05";
      system = "x86_64-linux"; 
      pkgs = nixpkgs.legacyPackages.${system};
      secrets = builtins.fromJSON (builtins.readFile ./.secrets.json);
      # Generate SSH/git configuration for each account defined in `.secrets.yaml`.
      # Each account entry becomes an SSH host alias and a git includeIf rule scoped 
      # to a directory (e.g. ~/personal/)
      gitAccounts = map (name: {
        alias = name;
        nameSecret = "git.${name}.name";          # Decrypted git user.name
        name = secrets.git.${name}.name;
        emailSecret = "git.${name}.email";        # Decrypted git user.email
        email = secrets.git.${name}.email;
        identityFile = "~/.ssh/github.${name}";   # SSH private key path on this machine (password)
        gitDir = "~/${name}/";                    # Directory where this identity is used
      }) (builtins.attrNames secrets.git);

    in
    {
      # Running `nixos-rebuild switch --flake .#nixos` builds whatever configuration is 
      # found at `nixosConfigurations.nixos`. This must match the hostname.
      nixosConfigurations.${hostname} = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit hostname username stateVersion gitAccounts; };
        modules = [
          ./configuration.nix
          # SOPs (Secrets OPerationS) https://github.com/getsops/sops
          sops-nix.nixosModules.sops
          # A module that integrates home-manager into the system build.
          home-manager.nixosModules.home-manager
          {
            # Use the system's Nix `nixpkgs` rather than resolving a separate copy.
            home-manager.useGlobalPkgs = true;
            # Build home-manager packages as part of the system closure.
            home-manager.useUserPackages = true;
            # Extra arguments passed to the module.
            home-manager.extraSpecialArgs = { inherit stateVersion gitAccounts; };
            # This loads plasma-manager as a shared home-manager module.
            home-manager.sharedModules = [ plasma-manager.homeModules.plasma-manager ];
            # Assigns the user's home configuration to use the configuration in `home.nix`.
            home-manager.users.${username} = import ./home.nix;
          }
        ];
      };
      devShells.${system}.default = pkgs.mkShell {
        buildInputs = with pkgs; [
          age
          sops
        ];
      };
    };
}
