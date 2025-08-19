#!/bin/bash
#
# Usage: deploy-config.sh <host> <flakeref>
#
# Options:
#   <host>     Host to SSH to as $USER
#   <flakeref> Flake reference pointing to NixOS configuration.
#
# Dumb script for deploying a NixOS configuration to a target machine.
# This is a separate script so that it can be swapped out so that these scripts
# can be reused in bizarro environments where special operations are requried to
# deploy OSes.
#
# This is stupid and inflexible, we really need some proper deployment system
# here, but I dunno if anything exists that solves the particular problem we
# have here.

set -eu -o pipefail

source docopts.sh --auto -G "$@"

nixos-rebuild --flake "$flakeref" --target-host "$USER@$ARGS_host" --use-remote-sudo switch

# Use boot.json as a funny hack to detect if we need to reboot. I am not
# that confident in this trick...
ssh "$USER@$ARGS_host" <<EOF
    if ! cmp /run/current-system/boot.json /run/booted-system/boot.json; then
        sudo reboot
    else
        echo -e "\n\n\n  !!! NOT REBOOTING as boot.json is unchanged !!! \n\n"
    fi
EOF

# Wait until the SSH port becomes visible.
# -z = scan only,  -w5 = 5s timeout
deadline_s=$(($(date +%s) + 120))
while ! ssh -o ConnectTimeout=5 "$USER@$ARGS_host" echo; do
    current_time_s=$(date +%s)
    if (( current_time_s > deadline_s )); then
        echo "Timed out after 2m waiting for host SSH port to appear"
        exit 1
    fi
    sleep 1
done
