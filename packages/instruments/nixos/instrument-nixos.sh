#!/bin/bash

set -euo pipefail

usage() {
    echo "Usage: $0 [--before | --after]"
    exit 1
}

if [[ $# -eq 0 ]]; then
    usage
fi

case "$1" in
    --before)
        ;;
    --after)
        # Nothing to do, this is a one-shot instrument.
        exit 0
        ;;
    *)
        usage
        ;;
esac

cd "$KBN_INSTRUMENT_DIR"

nixos-version --json > nixos-version.json
readlink /run/current-system > nixos_current_system
readlink /run/booted-system > nixos_booted_system
cat /etc/os-release > os-release

if ! cmp nixos_current_system nixos_booted_system; then
    echo "current-system and booted-system differ. Cowardly refusing to continue, try rebooting target."
    exit 1
fi
