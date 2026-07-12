#!/usr/bin/env bash
set -euo pipefail

# Single entry point for Forgejo's Cloudflare Tunnel.
#
# Subcommands:
#   env <output-file>  Render Forgejo's public-hostname overrides from the
#                      decrypted secrets as a systemd EnvironmentFile. Runs
#                      as ExecStartPre of forgejo.service; writes an empty app.ini
#                      file when the domain is not configured, so Forgejo
#                      falls back to localhost.
#
#   run                Render the tunnel config and exec cloudflared.
#                      Main process of cloudflared-forgejo.service.
#
# The following arguments must be provided:
# ------------------------------------------------------------------------------------
#   YQ_BIN, ENVSUBST_BIN                        tool paths (default to PATH lookups)
#   APP_INI_TEMPLATE                            ini template path for `env`
#   CONFIG_TEMPLATE                             template path for `run`
#   SECRETS_FILE                                sops secrets file (`env` only)
#   CLOUDFLARED_BIN, FORGEJO_HTTP_PORT,
#   CREDENTIALS_DIRECTORY, RUNTIME_DIRECTORY    (`run` only, via systemd)
# ------------------------------------------------------------------------------------

YQ_BIN="${YQ_BIN:-yq}"
ENVSUBST_BIN="${ENVSUBST_BIN:-envsubst}"

read_secret() {
  "$YQ_BIN" -r "$1 // \"\"" "$2" 2>/dev/null || true
}

# Translates rendered ini on stdin into the FORGEJO__SECTION__KEY=value
# env-var form Forgejo's environment-to-ini expects, tracking [section]
# headers as it goes:
# https://codeberg.org/forgejo/forgejo/src/branch/forgejo/contrib/environment-to-ini/environment-to-ini.go
ini_to_env() {
  local section="" line key value
  while IFS= read -r line; do
    case "$line" in
      \[*\])
        section="${line#[}"
        section="${section%]}"
        section="${section^^}"
        ;;
      [A-Z_]*\ =\ *)
        key="${line%% = *}"
        value="${line#* = }"
        printf 'FORGEJO__%s__%s=%s\n' "$section" "$key" "$value"
        ;;
    esac
  done
}

render_env() {
  local output_file="$1"
  local secrets_file="${SECRETS_FILE:-/run/secrets/secrets.yaml}"
  local domain sitekey secret rendered
  domain=$(read_secret '.forgejo.domain' "$secrets_file")
  sitekey=$(read_secret '.forgejo."turnstile-sitekey"' "$secrets_file")
  secret=$(read_secret '.forgejo."turnstile-secret"' "$secrets_file")

  if [ -n "$domain" ]; then
    rendered=$(
      DOMAIN="$domain" TURNSTILE_SITEKEY="$sitekey" TURNSTILE_SECRET="$secret" \
        "$ENVSUBST_BIN" '$DOMAIN $TURNSTILE_SITEKEY $TURNSTILE_SECRET' \
        < "$APP_INI_TEMPLATE" | ini_to_env
    )

    # Without both Turnstile keys, drop the [service] captcha overrides
    # entirely: ENABLE_CAPTCHA=true with empty keys would break signup.
    # Registration then falls back to manual admin approval alone.
    if [ -z "$sitekey" ] || [ -z "$secret" ]; then
      rendered=$(printf '%s\n' "$rendered" | grep -v '^FORGEJO__SERVICE__' || true)
    fi

    printf '%s\n' "$rendered" > "$output_file"
  else
    : > "$output_file"
  fi

  chmod 600 "$output_file"
}

run_tunnel() {
  local secrets_file="${CREDENTIALS_DIRECTORY}/secrets.yaml"
  local config_file="${RUNTIME_DIRECTORY}/config.yml"
  local domain tunnel_id
  domain=$(read_secret '.forgejo.domain' "$secrets_file")
  tunnel_id=$(read_secret '.forgejo."tunnel-id"' "$secrets_file")

  if [ -z "$domain" ] || [ -z "$tunnel_id" ]; then
    echo "forgejo.domain / forgejo.tunnel-id not set in secrets; not starting the tunnel."
    exit 0
  fi

  DOMAIN="$domain" \
  TUNNEL_ID="$tunnel_id" \
  TUNNEL_CREDS="${CREDENTIALS_DIRECTORY}/tunnel.json" \
  HTTP_PORT="${FORGEJO_HTTP_PORT:-3000}" \
    "$ENVSUBST_BIN" '$DOMAIN $TUNNEL_ID $TUNNEL_CREDS $HTTP_PORT' \
    < "$CONFIG_TEMPLATE" > "$config_file"

  exec "${CLOUDFLARED_BIN:-cloudflared}" tunnel --no-autoupdate --config "$config_file" run
}

case "${1:-}" in
  env) render_env "$2" ;;
  run) run_tunnel ;;
  *)
    echo "usage: $0 {env <output-file>|run}" >&2
    exit 64
    ;;
esac
