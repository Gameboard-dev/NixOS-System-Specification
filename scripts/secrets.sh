#!/usr/bin/env bash
set -euo pipefail

# Single entry point for reading the sops-decrypted secrets file
# (/run/secrets/secrets.yaml, decrypted at activation by configuration.nix).
#
# Usage:
#   secrets.sh <path-to-yq> query <yq-expression> [secrets-file]
#       Print one value; prints nothing if the file is missing/unreadable
#       (e.g. SOPS not set up yet). Used by forgejo.nix service units and
#       scripts/setup-cloudflared.sh.
#
#   secrets.sh <path-to-yq> render
#       Render ~/.ssh/config, ~/.gitconfig and per-account git identity
#       fragments from the git profiles in the secrets file. Invoked by
#       home-manager activation (home.nix).

if [ $# -lt 2 ]; then
	echo "usage: secrets.sh <path-to-yq> query <expr> [file] | render" >&2
	exit 1
fi

YQ="$1"
MODE="$2"
SECRETS="/run/secrets/secrets.yaml"

# query <expr> [file]: empty output (success) when the file isn't readable.
query() {
	local file="${2:-$SECRETS}"
	[ -r "$file" ] || return 0
	"$YQ" e "$1" "$file"
}

if [ "$MODE" = "query" ]; then
	query "$3" "${4:-}"
	exit 0
fi

if [ "$MODE" != "render" ]; then
	echo "secrets.sh: unknown mode '$MODE'" >&2
	exit 1
fi

SSH_CONFIG="$HOME/.ssh/config"
GIT_CONFIG="$HOME/.gitconfig"
PROFILE_DIR="$HOME/.config/git/profiles"

if [ ! -r "$SECRETS" ]; then
	echo "secrets.sh: $SECRETS not readable; skipping" >&2
	exit 0
fi

mkdir -p "$HOME/.ssh" "$PROFILE_DIR"
: > "$SSH_CONFIG"
: > "$GIT_CONFIG"

for ALIAS in $(query '.profiles.git | keys | .[]'); do
	NAME=$(query ".profiles.git.\"$ALIAS\".name")
	EMAIL=$(query ".profiles.git.\"$ALIAS\".email")
	SSH_KEY=$(query ".profiles.git.\"$ALIAS\".\"ssh-key\"")
	PROFILE="$PROFILE_DIR/$ALIAS"

	cat >> "$SSH_CONFIG" <<-YML
		Host github.com-$ALIAS
		  HostName github.com
		  User git
		  IdentityFile $SSH_KEY
	YML

	cat > "$PROFILE" <<-INI
		[user]
		  name = $NAME
		  email = $EMAIL
	INI

	while IFS= read -r DIR; do
		EXPANDED="${DIR/#\~/$HOME}"
		cat >> "$GIT_CONFIG" <<-INI
			[includeIf "gitdir:$EXPANDED/"]
			  path = $PROFILE
		INI
	done < <(query ".profiles.git.\"$ALIAS\".directories[]")

done

chmod 600 "$SSH_CONFIG"
