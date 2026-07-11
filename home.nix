# Home Manager is a Nix-powered tool for reproducible management of the contents of users’ home directories.
# https://nix-community.github.io/home-manager/introduction.html
{ pkgs, stateVersion, gitAccounts, ... }:
{
  # home.stateVersion must match the stateVersion in flake.nix to ensure
  # compatibility with the system's on-disk database format, passed via
  # `home-manager.extraSpecialArgs` in `flake.nix`
  home.stateVersion = stateVersion;

  # Configure vscodium language extensions
  programs.vscodium = {
    enable = true;
    profiles.default.extensions = with pkgs.vscode-extensions; [
      jnoortheen.nix-ide
    ];
  };

  # SSH configuration for multiple GitHub accounts.
  programs.ssh = {
    enable = gitAccounts != [ ];
    matchBlocks = builtins.listToAttrs (map (a: {
      name = "github.com-${a.alias}";
      value = {
        hostname = "github.com";
        user = "git";
        identityFile = a.identityFile;
      };
    }) gitAccounts);
  };

  programs.git = {
    enable = gitAccounts != [ ];
    includeIf = map (a: {
      condition = "gitdir:${a.gitDir}";
      config = {
        user.name = a.name;
        user.email = a.email;
      };
    }) gitAccounts;
  };

  # Plasma-Manager is a module for Home Manager that lets users
  # configure the KDE Plasma desktop declaratively using Nix.
  programs.plasma = {
      enable = true;

      # Configure a panel (taskbar) at the bottom of the screen with
      # options in: https://github.com/nix-community/plasma-manager/blob/trunk/modules/panels.nix
      panels = [
        {
          location = "bottom";
          floating = false;
          screen = "all";
          alignment = "center";

          # Available widgets: kickoff (app menu), icontasks (window list),  marginsseparator (spacer), ...
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
