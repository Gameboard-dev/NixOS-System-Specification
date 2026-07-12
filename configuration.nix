{ config, pkgs, lib, hostname, username, stateVersion, gitAccounts, ... }:
let
  locale = "en_GB.UTF-8";
in
{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = hostname;
  networking.networkmanager.enable = true;

  # [TimeZone]
  time.timeZone = "Europe/London";

  # [Language]
  i18n.defaultLocale = locale;
  i18n.extraLocaleSettings = lib.genAttrs [
    "LC_ADDRESS"
    "LC_IDENTIFICATION"
    "LC_MEASUREMENT"
    "LC_MONETARY"
    "LC_NAME"
    "LC_NUMERIC"
    "LC_PAPER"
    "LC_TELEPHONE"
    "LC_TIME"
  ] (_: locale);

  # [GUI Display]
  services.xserver.enable = true;

  # [Desktop (Plasma6 KDE)]
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;

  # [Keyboard Layout]
  services.xserver.xkb = { layout = "gb"; variant = ""; };
  console.keyMap = "uk";

  services.printing.enable = true;

  # [Audio/Video] https://wiki.nixos.org/wiki/PipeWire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = [ "networkmanager" "wheel" ];
  };

  programs.firefox.enable = true;

  nix.settings.experimental-features = [ "nix-command" "flakes" ];

  # Automatically clean up older configurations. Remove NixOS builds weekly to free up disk space.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };

  # If free space in `/nix/store` drops below min-free mid-build Nix garbage-collects until max-free bytes are free or until no garbage is left to remove
  nix.settings.min-free = 128000000;
  nix.settings.max-free = 1000000000;

  # https://search.nixos.org/packages
  environment.systemPackages = with pkgs; [
    vscodium
    proton-vpn
    git
    jq
  ];
  system.stateVersion = stateVersion;
  sops = {
    age.keyFile = "/root/.config/sops/age/keys.txt";
    # key = "" means "do not extract a single value; decrypt the whole document".
    secrets."secrets" = {
      sopsFile = ./.secrets.encrypted.yaml;
      format = "yaml";
      key = "";
      path = "/run/secrets/secrets.yaml";
      owner = username;
      mode = "0400";
    };
  };

}
