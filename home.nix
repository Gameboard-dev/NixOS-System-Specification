{ pkgs, lib, stateVersion, ... }:
{
  home.stateVersion = stateVersion;
  # [VSCodium Extensions]
  programs.vscodium = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide
      anthropic.claude-code
    ];
  };
  home.packages = with pkgs; [
    nixd
  ];
  # [renderGitProfiles]
  # Renders ~/.ssh/config, ~/.gitconfig and per-account git identity fragments
  # from the sops-decrypted /run/secrets/secrets.yaml at every activation.
  # programs.ssh / programs.git must stay unmanaged by home-manager.
  home.activation.renderGitProfiles = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${pkgs.bash}/bin/bash ${./.render-secrets.sh} "${pkgs.yq-go}/bin/yq"
  '';
  # [Home Manager // Plasma-Manager]
  # Declaratively configure KDE Plasma user desktop using Nix.
  programs.plasma = {
      enable = true;
      # [Panels] https://github.com/nix-community/plasma-manager/blob/trunk/modules/panels.nix
      panels = [
        {
          location = "bottom";
          floating = false;
          screen = "all";
          alignment = "center";
          # [Panels-Widgets]
          # https://github.com/nix-community/plasma-manager/tree/trunk/modules/widgets
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
