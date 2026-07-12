#!/usr/bin/env bash
set -euo pipefail

# Renders SSH and git identity config from the sops-decrypted secrets file.
# Invoked by home-manager activation (home.nix); $1 = path to yq binary.

YQ="$1"
SECRETS="/run/secrets/secrets.yaml"
SSH_CONFIG="$HOME/.ssh/config"
GIT_CONFIG="$HOME/.gitconfig"
PROFILE_DIR="$HOME/.config/git/profiles"

if [ ! -r "$SECRETS" ]; then
	echo "render-secrets: $SECRETS not readable; skipping" >&2
	exit 0
fi

mkdir -p "$HOME/.ssh" "$PROFILE_DIR"
: > "$SSH_CONFIG"
: > "$GIT_CONFIG"

query() { "$YQ" e "$1" "$SECRETS"; }

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