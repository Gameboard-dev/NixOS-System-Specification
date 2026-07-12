# NixOS System Configuration

A flake-based, single-machine NixOS configuration using [home-manager](https://github.com/nix-community/home-manager) and [plasma-manager](https://github.com/nix-community/plasma-manager) for a declarative KDE Plasma desktop.

This repository does **not** include `hardware-configuration.nix`, since that file is machine-specific (disk UUIDs, kernel modules, CPU type). You generate it fresh on the target machine as part of installation, following the steps below.

## Prerequisites

- A spare USB drive, 8 GB or larger - its contents will be erased.
- A second computer to create the installer USB from.
- The target machine you're installing NixOS onto.

## 1. Download the NixOS ISO

Go to the [official NixOS download page](https://nixos.org/download/) and download the **Graphical ISO image** for your architecture.

## 2. Create a bootable USB with balenaEtcher

1. Download and install [balenaEtcher](https://etcher.balena.io/).
2. Open balenaEtcher, click **Flash from file**, and select the NixOS ISO you downloaded.
3. Select your USB drive as the target.
4. Click **Flash** and wait for it to complete. This erases the USB drive.

## 3. Boot the target machine from the USB

1. Plug the USB drive into the target machine.
2. Restart the machine and enter its boot menu (commonly `F2`, `F12`, `Esc`, or `Del`, depending on the manufacturer).
3. Select the USB drive as the boot device.
4. NixOS boots into a live graphical installer environment.

## 4. Install NixOS

Follow the graphical installer to partition your disk and install a minimal NixOS system. If you want disk encryption (as this configuration assumes), select an encrypted (LUKS) option during partitioning.

Once the installer finishes, reboot and remove the USB drive. You should land on a fresh, minimal NixOS installation.

## 5. Clone the repository

Log in to your new NixOS system, connect to the internet, and clone this repository into `/etc/nixos`:

```bash
sudo rm -rf /etc/nixos
sudo git clone <this-repository-url> /etc/nixos
cd /etc/nixos
```

`/etc/nixos` is the conventional location NixOS tooling expects, though flakes work from any directory.

## 6. Generate `hardware-configuration.nix`

This is the one file specific to your machine, and it isn't included in the repo. It is normally created by the installer in step 4, but you can regenerate it at any time with:

```bash
sudo nixos-generate-config --show-hardware-config > /etc/nixos/hardware-configuration.nix
```

This inspects your disks, filesystems, and hardware and writes a `hardware-configuration.nix` tailored to your machine - including the architecture (`nixpkgs.hostPlatform`), which the flake reads automatically.


### Forgejo

`forgejo.nix` runs a [Forgejo](https://forgejo.org/) git forge backed by the local PostgreSQL (Unix socket, peer auth - no database password exists). Nightly `forgejo dump` backups land in `/var/lib/forgejo/dump`. 

The web UI and git SSH are only reachable through an outbound-only Cloudflare Tunnel. Nothing listens beyond loopback and no inbound ports are opened.

This also ensures compatibility with WAN networks since the host machine sets up 
the outbound connection.

The public domain and tunnel ID are not in the repo: they live in the encrypted secrets file under `forgejo:` (in `.secrets.example.yaml`) and are read at service start from the decrypted `/run/secrets/secrets.yaml`. While they are empty, the system still builds and Forgejo runs on loopback/localhost - the tunnel is simply skipped.

To set up the tunnel:

1. Set `forgejo.domain` in the secrets file (`sudo sops .secrets.encrypted.yaml`), then rebuild so `/run/secrets/secrets.yaml` refreshes. The web UI lives at that domain; git SSH uses `ssh.<domain>`.

2. Run the setup script - it logs in to Cloudflare, creates the tunnel, routes DNS for both hostnames, and installs the credentials at `/etc/cloudflared/forgejo-tunnel.json`:

```bash
bash scripts/cloudflared.setup.sh
```

3. Store the tunnel ID it prints as `forgejo.tunnel-id` in the secrets file, and rebuild again.

**First admin account** - registration is disabled, so create it from the CLI:

```bash
sudo -u forgejo env FORGEJO_WORK_DIR=/var/lib/forgejo \
  forgejo admin user create --admin --username <name> \
  --email <email> --random-password
```

```bash
sudo -u forgejo env FORGEJO_WORK_DIR=/var/lib/forgejo \
  forgejo admin user create \
  --admin \
  --username Walainski \
  --email js5859133@gmail.com \
  --password "h8B"
```

**Cloning over SSH** - git traffic rides the tunnel too, so clients need `cloudflared` installed locally and this in `~/.ssh/config`:

```ini
Host ssh.forgejo.example.com
  ProxyCommand cloudflared access ssh --hostname %h
```

Add your SSH public key in the Forgejo web UI as usual; 
the host's OpenSSH handles git connections (key-only, no passwords).

## 7. Update `flake.nix` for your setup

Open `flake.nix` and adjust the `hostname` and `username` values in the `let` block to match how you wish to appear on the network, and your login username:

```nix
hostname = "nixos";
username = "megatron";
```

### Trusted Platform Module (TPM) Disk Decryption

Only relevant if you have a TPM chip and chose disk encryption during installation ([step 4](#4-install-nixos)). With TPM2, your disks unlock automatically at boot without a password.

```bash
bash scripts/tpm.enroll.sh
```

This lists every LUKS partition it finds, asks for confirmation, then prompts for your existing LUKS passphrase to enroll each one. On machines without a TPM it exits harmlessly without changing anything.

The password stays enrolled as a fallback, so this is safe to set up: if unsealing fails (e.g. after a firmware update), you are simply prompted for it as before.


## 8. SSH Key Persistence for Github

This configuration uses [sops-nix](https://github.com/Mic92/sops-nix) to keep the configuration for multiple Git accounts encrypted in the repository. Secrets are decrypted at build time using a private key that never leaves the machine.

### 8.1. Generate SSH keys for each of your Github accounts

```bash
bash create-ssh.sh
```

For each account, sign in to the corresponding GitHub account, go to
**Settings → SSH and GPG keys → New SSH key**, and paste in the matching
public key. Private keys (`github_personal`, `github_work`, without the
`.pub` suffix) stay on the machine and must never be committed.

### 8.2. Generate an Encryption Key with SOPS:

```bash
sudo mkdir -p /root/.config/sops/age
nix develop # age + sops
sudo age-keygen -o /root/.config/sops/age/keys.txt
```

Configure `.sops.yaml` to use the public key
and encrypt `.secrets.json` in place.

```bash
nix develop # sops + age
sops --encrypt .secrets.yaml > .secrets.encrypted.yaml
rm .secrets.yaml
```

The file can be viewed or edited using:

```bash
export EDITOR=nano
sudo sops .secrets.encrypted.yaml
```

## 9. Build and switch

Preview the changes without applying them:

```bash
sudo nixos-rebuild dry-run --flake .#nixos
```

If there are no errors, apply the changes:

```bash
sudo nixos-rebuild switch --flake .#nixos
```

Your system rebuilds according to `configuration.nix` and `home.nix`, and boots into the configured environment.

## Maintenance

Roll back to the previous generation if something breaks:

```bash
sudo nixos-rebuild switch --rollback
```

Clean up older generations to free disk space:

```bash
sudo nix-collect-garbage -d                       # Keep only the current generation
sudo nix-collect-garbage --delete-older-than 30d  # Remove generations older than 30 days
```

Weekly automatic cleanup is already configured in `configuration.nix`.

## Notes

- `flake.lock` is committed to this repo and pins the exact versions of all inputs. Do not delete it - it's what makes the build reproducible.

- `hardware-configuration.nix` should **not** be copied between machines; regenerate it on each new machine using [step 6](#6-generate-hardware-configurationnix) above.


### Granting write access for passwordless editing

By default, `/etc/nixos` is owned by root. 
To edit and save files without password prompts, grant yourself temporary write access:

```bash
sudo chown -R megatron:users /etc/nixos
sudo chmod -R u+w /etc/nixos
```

When you're finished making changes, revert the permissions:

```bash
sudo chown -R root:root /etc/nixos
sudo chmod -R go-w /etc/nixos
```

## Alternative Installation Methods

While NixOS is primarily intended to be installed as the primary operating system, alternatives exist:

- **Windows Subsystem for Linux (WSL)**: Run NixOS inside Windows 10/11 without a separate partition. See the [NixOS-WSL guide](https://github.com/nix-community/NixOS-WSL).

- **Existing Linux distributions**: Convert a running Linux system to NixOS using [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) or [nixos-infect](https://github.com/elitak/nixos-infect). Useful for cloud servers or existing installations you want to repurpose.

- **AWS (Amazon Web Services)**: NixOS can be deployed to Amazon EC2 using the [official AMI](https://nixos.org/download/#nixos-amazon).

