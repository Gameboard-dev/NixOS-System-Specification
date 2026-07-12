{ pkgs, lib, hostname, username, stateVersion, ... }:

let
  locale = "en_GB.UTF-8";
in

{
  imports = [ ./hardware-configuration.nix ];

  # Boot loader configuration.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Network and hostname.
  networking.hostName = hostname;
  networking.networkmanager.enable = true;

  # Localization.
  time.timeZone = "Europe/London";
  i18n.defaultLocale = locale;
  i18n.extraLocaleSettings = lib.genAttrs [
    "LC_ADDRESS" "LC_IDENTIFICATION" "LC_MEASUREMENT" "LC_MONETARY"
    "LC_NAME" "LC_NUMERIC" "LC_PAPER" "LC_TELEPHONE" "LC_TIME"
  ] (_: locale);

  # Display server and desktop environment.
  services.xserver.enable = true;
  services.desktopManager.plasma6.enable = true;
  services.displayManager.sddm.enable = true;

  # Keyboard layout.
  services.xserver.xkb = { layout = "gb"; variant = ""; };
  console.keyMap = "uk";

  # Printing support.
  services.printing.enable = true;

  # Audio: PipeWire replaces PulseAudio and JACK.
  # https://wiki.nixos.org/wiki/PipeWire
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # User account.
  users.users.${username} = {
    isNormalUser = true;
    description = username;
    extraGroups = [ "networkmanager" "wheel" ];
  };

  # Default packages.
  programs.firefox.enable = true;
  environment.systemPackages = with pkgs; [
    vscodium
    proton-vpn
    git
    jq
  ];

  # Nix configuration.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  nix.settings.min-free = 128000000;
  nix.settings.max-free = 1000000000;

  # Secrets management via SOPS.
  # Decrypts the entire secrets file at activation time: Empty key means decrypt the entire file as one blob.
  # The age private key at keyFile is used only on this machine. Never committed.
  sops = {
    age.keyFile = "/root/.config/sops/age/keys.txt";
    secrets."secrets" = {
      sopsFile = ./.secrets.encrypted.yaml;
      format = "yaml";
      key = "";  
      path = "/run/secrets/secrets.yaml";
      owner = username;
      mode = "0400";
    };
  };

  # System state version: do not change.
  system.stateVersion = stateVersion;

  # Requires for Claude Code in VS Code (home.nix)
  nixpkgs.config.allowUnfree = true;
}