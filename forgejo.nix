# Forgejo git forge backed by PostgreSQL, accessed via a Cloudflare Tunnel
{ config, pkgs, lib, ... }:

let
  httpPort = 3000;
  secretsFile = "/run/secrets/secrets.yaml";
  credentialsFile = "/etc/cloudflared/forgejo-tunnel.json";
  domainEnvFile = "${config.services.forgejo.stateDir}/domain.env";
in
{
  services.forgejo = {
    enable = true;
    database.type = "postgres";
    
    # LFS (Large File Storage)
    lfs.enable = true; 
    
    # Whether to enable periodic dumps via the built-in `forgejo dump` command.
    # The 'age' parameter determines how old a file needs to be, to qualify for deletion.
    # Whatever threat takes out the machine takes the backups with it; 
    # An off-machine copy (via rsync) should periodically be made.
    dump = {
      enable = true;
      type = "tar.zst";
      age = "4w";
    };

    # Keys below map 1:1 onto Forgejo's app.ini and are documented
    # here: https://forgejo.org/docs/latest/admin/config-cheat-sheet/
    settings = {
      server = {
        HTTP_ADDR = "127.0.0.1";
        HTTP_PORT = httpPort;
      };
      
      # Served over HTTPS at the Cloudflare edge, so cookies MUST be Secure.
      session.COOKIE_SECURE = true;
      
      # The minimum length of a password for Forgejo user/admin accounts.
      security.MIN_PASSWORD_LENGTH = 16;
      
      service = {
        # When a domain is configured, the render step overrides this at runtime --
        # registration is open if and only if both turnstile-* secrets are set, 
        # so public signup is never open without the Turnstile CAPTCHA 
        # (see templates/forgejo/app.ini).
        DISABLE_REGISTRATION = false;
        # REGISTER_MANUAL_CONFIRM keeps every new account inactive until
        # an admin approves it (Site Administration -> Identity & Access).
        REGISTER_MANUAL_CONFIRM = true;
        # Whether to hide the user email address by default.
        DEFAULT_KEEP_EMAIL_PRIVATE = true;
      };

      picture = {
        # Prevents the user's email address being leaked to `gravatar.com` when fetching profile images.
        DISABLE_GRAVATAR = true;
        # Prevents the same lookup against federated avatar providers (e.g. Libravatar).
        ENABLE_FEDERATED_AVATAR = false;
      };

      # Hides the Forgejo running version, so it can't be used to fingerprint for known vulnerabilities.
      other.SHOW_FOOTER_VERSION = false;

      # Disables code search for multiple repositories to save on disk space.
      indexer.REPO_INDEXER_ENABLED = false;

      # The Forgejo running version is pinned by nixpkgs, 
      # it should NOT be managed by Forgejo's own update daemon.
      "cron.update_checker".ENABLED = false;

      # Forgejo Actions (CI/CD)
      # https://forgejo.org/docs/latest/admin/actions/
      actions.ENABLED = true;
    };
  };

  # Renders the public-hostname env overrides from the decrypted secrets before
  # Runs as root ("+" prefix) because only root may read the secrets.
  systemd.services.forgejo = {
    environment = {
      YQ_BIN = "${pkgs.yq-go}/bin/yq";
      ENVSUBST_BIN = "${pkgs.gettext}/bin/envsubst";
      APP_INI_TEMPLATE = "${./templates/forgejo/app.ini}";
      SECRETS_FILE = secretsFile;
    };
    serviceConfig = {
      # The script 'forgejo.tunnel.setup.sh' is a single entry point with two subcommands,
      # The ExecStartPre command here executes briefly before Forgejo starts, 
      # renders the FORGEJO__SERVER__* overrides from the secrets file 
      # into domain.env, and exits. mkBefore ensures our render is the FIRST ExecStartPre, 
      # or the overrides arrive too late and Forgejo falls back to http://localhost:3000/.
      # See the expected structure in: https://codeberg.org/forgejo/forgejo/src/branch/forgejo/contrib/environment-to-ini/environment-to-ini.go
      ExecStartPre = lib.mkBefore [ "+${pkgs.bash}/bin/bash ${./scripts/forgejo.tunnel.setup.sh} env ${domainEnvFile}" ];
      EnvironmentFile = "-${domainEnvFile}";
    };
  };

  # Outbound-only tunnel to Cloudflare's edge: the web UI and git SSH are
  # reachable through WAN without opening any inbound firewall port. 
  # Forgejo runs on localhost if Cloudflare is not configured yet.
  systemd.services.cloudflared-forgejo = {
    description = "Cloudflare Tunnel for Forgejo";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    after = [ "network-online.target" ];
    unitConfig.ConditionPathExists = [ credentialsFile secretsFile ];
    serviceConfig = {
      # systemd loads these as root and exposes them read-only to the
      # unprivileged service user under $CREDENTIALS_DIRECTORY.
      LoadCredential = [
        "secrets.yaml:${secretsFile}"
        "tunnel.json:${credentialsFile}"
      ];
      DynamicUser = true;
      RuntimeDirectory = "cloudflared-forgejo";
      Restart = "on-failure";
      RestartSec = "5s";
    };
    environment = {
      FORGEJO_HTTP_PORT = toString httpPort;
      CLOUDFLARED_BIN = "${pkgs.cloudflared}/bin/cloudflared";
      YQ_BIN = "${pkgs.yq-go}/bin/yq";
      ENVSUBST_BIN = "${pkgs.gettext}/bin/envsubst";
      CONFIG_TEMPLATE = "${./templates/cloudflared/config.yml}";
    };
    # Renders the tunnel config from its template if the domain is configured (templates/cloudflared/config) 
    # and then execs into cloudflared, which keeps running as the service's long-lived process.
    # Otherwise writes an empty file Forgejo falls back to localhost if the tunnel is not set up.
    script = "exec ${pkgs.bash}/bin/bash ${./scripts/forgejo.tunnel.setup.sh} run";
  };
  # Forgejo Actions runner: executes CI jobs inside podman containers on the
  # isolated bridge network -- jobs reach Forgejo only via the public domain,
  # and never see the host's network namespace or the podman socket
  systemd.services.forgejo-runner = {
    description = "Forgejo Actions Runner";
    wantedBy = [ "multi-user.target" ];
    wants = [ "network-online.target" ];
    # Registration and job traffic go through the public domain, 
    # so Forgejo and the tunnel should be active/available.
    after = [
      "network-online.target"
      "podman.socket"
      "forgejo.service"
      "cloudflared-forgejo.service"
    ];
    unitConfig.ConditionPathExists = [ secretsFile ];
    serviceConfig = {
      DynamicUser = true;
      LoadCredential = [ "secrets.yaml:${secretsFile}" ];
      # Persists the runner registration (.runner) and build cache across
      # restarts at /var/lib/forgejo-runner.
      StateDirectory = "forgejo-runner";
      # Grants access to /run/podman/podman.sock (socket group "podman").
      SupplementaryGroups = [ "podman" ];
      Restart = "on-failure";
      RestartSec = "5s";
    };
    environment = {
      # The runner daemon talks to rootful podman over its Docker-compatible API socket
      DOCKER_HOST = "unix:///run/podman/podman.sock";
      HOME = "/var/lib/forgejo-runner";
      YQ_BIN = "${pkgs.yq-go}/bin/yq";
      RUNNER_BIN = "${pkgs.forgejo-runner}/bin/forgejo-runner";
      RUNNER_CONFIG = "${./templates/forgejo/runner.yml}";
      RUNNER_NAME = "${config.networking.hostName}-runner";
      RUNNER_LABELS = "docker:docker://node:20-bookworm";
    };
    script = "exec ${pkgs.bash}/bin/bash ${./scripts/forgejo.tunnel.setup.sh} runner";
  };
  # Puts Forgejo CLI on PATH.
  environment.systemPackages = [ config.services.forgejo.package ];
}
