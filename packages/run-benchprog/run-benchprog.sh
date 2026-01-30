#!/bin/bash

set -eu -o pipefail

#
# Stupid args boilerplate
#

FALBA_DB=
COLLECT_FILES=()
INSTRUMENT_VMSTAT=false

PARSED_ARGUMENTS=$(getopt -o d:c: --long falba-db:,collect:,instruments: -- "$@")
# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    echo "Error: Failed to parse arguments." >&2
    usage
    exit 1
fi

eval set -- "$PARSED_ARGUMENTS"
while true; do
    case "$1" in
        -d|--falba-db)
            FALBA_DB="$2"
            shift 2
            ;;
        -c|--collect)
            COLLECT_FILES+=("$2")
            shift 2
            ;;
        --instruments)
            # TODO: make this generic isntead of hardcoding vmstat here.
            if [ "$2" == "vmstat" ]; then
                INSTRUMENT_VMSTAT=true
            else
                echo "Error: Unsupported instrument '$2'. Only 'vmstat' is supported." >&2
                exit 1
            fi
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unexpected argument, script bug? $1" >&2
            exit 1
            ;;
    esac
done

if [ "$FALBA_DB" == "" ] || [ ! -d "$FALBA_DB" ]; then
    echo "--falba-db must point to an existing Falba database."
    exit 1
fi

if [ $# -ne 2 ]; then
    echo "Usage: $0 [opts] SSH_TARGET BENCHPROG"
    exit 1
fi

SSH_TARGET="$1"
BENCHPROG="$2"

#
# End stupid args boilerplate
#

nix copy --to ssh-ng://"$SSH_TARGET" "$BENCHPROG"
# TODO how should we implement installing instruments?
if [ "$INSTRUMENT_VMSTAT" = true ]; then
    nix copy --to ssh-ng://"$SSH_TARGET" "$(which instrument-vmstat)"
fi

# Fetch generic target data
host_info_dir="$(mktemp -d)"
nixos_version_json="$host_info_dir"/nixos-version.json
ssh "$SSH_TARGET" "nixos-version --json" > "$nixos_version_json"
ssh "$SSH_TARGET" "readlink /run/current-system" > "$host_info_dir"/nixos_current_system
ssh "$SSH_TARGET" "readlink /run/booted-system" > "$host_info_dir"/nixos_booted_system

if ! cmp "$host_info_dir"/nixos_current_system "$host_info_dir"/nixos_booted_system; then
    echo "current-system and booted-system differ. Cowardly refusing to continue, try rebooting target."
    exit 1
fi

# Collect additional requested files
for remote_file in "${COLLECT_FILES[@]}"; do
    scp "$SSH_TARGET:$remote_file" "$host_info_dir/" || echo "Warning: Failed to collect $remote_file" >&2
done

# Figure out the command to run
package_path=$(nix eval --raw "$BENCHPROG")
executable_name=$(nix eval --raw "$BENCHPROG.meta.mainProgram")
executable_path="$package_path/bin/$executable_name"

# Setup Remote Directories
remote_tmpdir=$(ssh "$SSH_TARGET" mktemp -d)

# Handle Instrumentation Setup
if [ "$INSTRUMENT_VMSTAT" = true ]; then
    remote_inst_dir="$(ssh "$SSH_TARGET" mktemp -d)"
    # shellcheck disable=SC2029
    ssh "$SSH_TARGET" "KBN_INSTRUMENT_DIR=$remote_inst_dir $(which instrument-vmstat) --before"
fi

# Run the benchprog
ssh "$SSH_TARGET" "$executable_path" --out-dir "$remote_tmpdir"

# Handle Instrumentation Teardown
if [ "$INSTRUMENT_VMSTAT" = true ]; then
    # shellcheck disable=SC2029
    ssh "$SSH_TARGET" "KBN_INSTRUMENT_DIR=$remote_inst_dir $(which instrument-vmstat) --after"
    rsync -avz "$SSH_TARGET:$remote_inst_dir/" "$host_info_dir/instrumentation/"
fi

# Fetch benchmark results
local_tmpdir="${TMPDIR:-/tmp}/$(basename "$remote_tmpdir")"
rsync -avz "$SSH_TARGET:$remote_tmpdir/" "$local_tmpdir/"

# Import everything to Falba
# We include the instrumentation data by passing the $host_info_dir glob
falba import --test-name "$executable_name" --result-db "$FALBA_DB" "$local_tmpdir" "$host_info_dir"/**