#!/usr/bin/env bash
set -euo pipefail

# Enrolls every LUKS partition with the TPM2 chip so drives unlock
# automatically at boot. The existing password remains as a fallback.
# Asks for the current LUKS passphrase once per partition.
if [[ ! -e /dev/tpmrm0 && ! -e /dev/tpm0 ]]; then
  echo "Error: no TPM2 device found. Nothing to enroll." >&2
  exit 1
fi

# LUKS partitions report FSTYPE "crypto_LUKS" whether or not they are
# currently unlocked, so this also catches swap that isn't mounted yet.
mapfile -t uuids < <(
  lsblk --noheadings --raw --output UUID,FSTYPE |
    awk '$2 == "crypto_LUKS" { print $1 }' |
    sort -u
)

if (( ${#uuids[@]} == 0 )); then
  echo "No LUKS partitions found." >&2
  exit 1
fi

echo "LUKS partitions to enroll:"
printf '  - %s\n' "${uuids[@]}"
echo

read -rp "Proceed with TPM2 enrollment? (y/N) " reply
if [[ ! $reply =~ ^[Yy]$ ]]; then
  echo "Cancelled."
  exit 0
fi

# Bind the key to Platform Configuration Registers (PCRs)
# (0) Firmware, (2) Bootloader, and (7) Secure Boot State.
for uuid in "${uuids[@]}"; do
  echo "Enrolling /dev/disk/by-uuid/${uuid}"
  sudo systemd-cryptenroll \
    --tpm2-device=auto \
    --tpm2-pcrs=0+2+7 \
    "/dev/disk/by-uuid/${uuid}"
done

echo "Done. Rebooting should now use TPM."
