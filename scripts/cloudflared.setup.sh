#!/usr/bin/env bash

set -euo pipefail

SECRETS=/run/secrets/secrets.yaml
CREDENTIALS=/etc/cloudflared/forgejo-tunnel.json
TUNNEL_NAME=forgejo

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
QUERY="$REPO_ROOT/scripts/secrets.sh"
ENCRYPTED="$REPO_ROOT/.secrets.encrypted.yaml"
EXAMPLE="$REPO_ROOT/.secrets.example.yaml"
REBUILD="sudo nixos-rebuild switch --flake $REPO_ROOT#nixos"

command -v cloudflared >/dev/null || { echo "cloudflared not on PATH" >&2; exit 1; }
command -v yq >/dev/null || { echo "yq not on PATH" >&2; exit 1; }

# Opens the encrypted secrets file in sops (decryption needs root's age key),
# then reminds how to apply the change. sops comes from the flake devShell.
edit_secrets() {
  if ! command -v sops >/dev/null; then
    echo "sops is not on PATH. Enter the dev shell first:" >&2
    echo "  cd $REPO_ROOT && nix develop" >&2
    echo "then re-run this script." >&2
    exit 1
  fi
  sudo sops "$ENCRYPTED"
  echo
  echo "Secrets updated. Apply them with:"
  echo "  $REBUILD"
  echo "then re-run this script."
  exit 1
}

domain=$(bash "$QUERY" "$(command -v yq)" query '.forgejo.domain // ""' "$SECRETS")
if [[ -z "$domain" ]]; then

  if [[ -e "$ENCRYPTED" ]]; then
    echo "forgejo.domain is not set in $ENCRYPTED - opening it in sops." >&2
    edit_secrets
  fi

  echo "$ENCRYPTED does not exist yet." >&2
  read -r -p "Create it from $EXAMPLE and open it for editing? [y/N] " answer
  
  if [[ "$answer" != [yY]* ]]; then
    echo "Aborted. Create it yourself with:" >&2
    echo "  cp $EXAMPLE $ENCRYPTED" >&2
    echo "  sops --encrypt --in-place $ENCRYPTED   # inside 'nix develop'" >&2
    exit 1
  else
    command -v sops >/dev/null || { echo "sops is not on PATH; run 'nix develop' first." >&2; exit 1; }
    cp "$EXAMPLE" "$ENCRYPTED"
    sops --encrypt --in-place "$ENCRYPTED"
    edit_secrets
  fi
fi

if [[ -e "$CREDENTIALS" ]]; then
  echo "$CREDENTIALS already exists - the tunnel appears to be set up." >&2
  exit 1
fi

if [[ ! -e "$HOME/.cloudflared/cert.pem" ]]; then
  cloudflared tunnel login
else
  echo "~/.cloudflared/cert.pem already exists - skipping login."
fi

cloudflared tunnel create "$TUNNEL_NAME"
cloudflared tunnel route dns "$TUNNEL_NAME" "$domain"
cloudflared tunnel route dns "$TUNNEL_NAME" "ssh.$domain"

credfile=$(ls -t "$HOME"/.cloudflared/*.json | head -1)
tunnel_id=$(basename "$credfile" .json)

sudo mkdir -p /etc/cloudflared
sudo mv "$credfile" "$CREDENTIALS"
sudo chown root:root "$CREDENTIALS"
sudo chmod 600 "$CREDENTIALS"

echo "Done. "

# The tunnel ID can be found in the Cloudflare console 
# at https://dash.cloudflare.com/ by searching 'tunnels'
echo "Your Cloudflare Tunnel ID is: $tunnel_id"
echo "Add it to the secrets file, then rebuild:"
echo "$REBUILD"
