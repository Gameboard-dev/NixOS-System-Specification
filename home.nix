{ pkgs, lib, stateVersion, ... }:

{
  home.stateVersion = stateVersion;

  # VSCodium extensions, declared so they're reproduced across rebuilds.
  programs.vscodium = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide    # Nix language server (nixd).
      anthropic.claude-code # Claude Code IDE integration.
    ];
  };

  # CLI tooling for the configured user only. 
  # System-wide packages belong in configuration.nix.
  home.packages = with pkgs; [
    nixd     
    nodejs
    curl
  ];

  # Renders ~/.ssh/config, ~/.gitconfig, and per-account identity fragments
  # from the git profiles in /run/secrets/secrets.yaml (decrypted from
  # .secrets.encrypted.yaml). This lets multiple git/SSH identities coexist
  # per-directory. See scripts/secrets.sh.
  home.activation.renderGitProfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.bash}/bin/bash ${./scripts/secrets.sh} "${pkgs.yq-go}/bin/yq" render
  '';

  # Declarative KDE Plasma desktop layout via plasma-manager, so the panel (taskbar)
  # and taskbar widget setup survives reinstalls instead of being configured by hand
  # through System Settings. The latest options/widgets are documented in:
  # https://github.com/nix-community/plasma-manager/blob/trunk/modules/
  programs.plasma = {
      enable = true;
      panels = [
        {
          location = "bottom";
          floating = false;
          screen = "all";
          alignment = "center";
          widgets = [
            "org.kde.plasma.kickoff"          
            "org.kde.plasma.icontasks"        
            "org.kde.plasma.marginsseparator" 
            "org.kde.plasma.systemtray"       
            "org.kde.plasma.digitalclock"     
          ];
        }
    ];
  };

}
