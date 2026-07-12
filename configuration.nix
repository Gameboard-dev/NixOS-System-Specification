{ pkgs, lib, hostname, username, stateVersion, ... }:

let
  locale = "en_GB.UTF-8";
in

{
  imports = [ ./hardware-configuration.nix ./forgejo.nix ];

  # Boot loader configuration.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # TPM (Trusted Platform Module) Drive Decryption. Falls back to password-based decryption on failure.
  security.tpm2.enable = true;
  boot.initrd.systemd.enable = true;

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

  # Keyboard.
  services.xserver.xkb = { layout = "gb"; variant = ""; };
  console.keyMap = "uk";

  # Printing.
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

  # Host SSH daemon: key-only auth, no root login. Also carries Forgejo's
  # git-over-SSH traffic (see forgejo.nix). Comment this out if not hosting
  # a publicly accessible SSH server
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      KbdInteractiveAuthentication = false;
      PermitRootLogin = "no";
    };
  };

  # PostgreSQL serving Forgejo
  services.postgresql = {
    enable = true;
    package = pkgs.postgresql_17;
    # When enableTCPIP is disabled, Postgres has no network listener at all, 
    # only the Unix socket. There is nothing to firewall, scan, or brute-force.
    enableTCPIP = false;
    authentication = lib.mkForce (builtins.readFile ./templates/postgresql/pg_hba.conf);
  };

  programs.firefox.enable = true;
  environment.systemPackages = with pkgs; [
    proton-vpn
    git
    jq # JSON
    yq-go # YAML
    cloudflared 
    nixfmt
  ];

  # Enable experimental features needed for the Flake to work.
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  
  # Automatically run the garbage collector every 30 days to clear up older builds.
  nix.gc = {
    automatic = true;
    dates = "weekly";
    options = "--delete-older-than 30d";
  };
  
  # Automatically garbage-collects when free disk space drops below min-free,
  # freeing up to max-free bytes per run. Prevents disk-space failures during builds.
  nix.settings.min-free = 128000000;
  nix.settings.max-free = 1000000000;

  # The empty key means SOPS decrypts the entire secrets file as one blob.
  # The age private keyFile is used only on this machine and NOT committed.
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

  # System state version. Specified in `flake.nix`.
  system.stateVersion = stateVersion;

  # Enable nix-ld to run dynamically linked binaries (required for Claude Code).
  programs.nix-ld.enable = true;

  # Enable proprietary/paid software (such as Claude Code)
  nixpkgs.config.allowUnfree = true;
}