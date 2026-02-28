#!/bin/bash

set -eu -o pipefail

#
# Stupid args boilerplate
#

FALBA_DB=.falba
COLLECT_FILES=()
INSTRUMENT_VMSTAT=false
SSH_PORT=22
DO_NIX_COPY=true

PARSED_ARGUMENTS=$(getopt -o d:c: --long falba-db:,collect:,instruments:,ssh-port:,no-copy -- "$@")
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
        # TODO: Figure out a less shitty way to configure SSH.
        --ssh-port)
            SSH_PORT="$2"
            shift 2
            ;;
        --no-copy)
            DO_NIX_COPY=false
            shift
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
    echo "If you intend to use $FALBA_DB, create that directory."
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

do_ssh() {
    local port_args
    if [ -n "$SSH_PORT" ]; then
        port_args="-p $SSH_PORT"
    else
        port_args=
    fi
    # shellcheck disable=SC2086,SC2029
    ssh $port_args "$SSH_TARGET" "$@"
}

if "$DO_NIX_COPY"; then
    nix copy --to ssh-ng://"$SSH_TARGET" "$BENCHPROG"
    # TODO how should we implement installing instruments?
    if [ "$INSTRUMENT_VMSTAT" = true ]; then
        nix copy --to ssh-ng://"$SSH_TARGET" "$(which instrument-vmstat)"
    fi
fi

# Fetch generic target data
host_info_dir="$(mktemp -d)"
nixos_version_json="$host_info_dir"/nixos-version.json
do_ssh "nixos-version --json" > "$nixos_version_json"
do_ssh "readlink /run/current-system" > "$host_info_dir"/nixos_current_system
do_ssh "readlink /run/booted-system" > "$host_info_dir"/nixos_booted_system
do_ssh "cat /etc/os-release" > "$host_info_dir/os-release"

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
remote_tmpdir=$(do_ssh mktemp -d)

# Handle Instrumentation Setup
if [ "$INSTRUMENT_VMSTAT" = true ]; then
    remote_inst_dir="$(do_ssh mktemp -d)"
    # shellcheck disable=SC2029
    do_ssh "KBN_INSTRUMENT_DIR=$remote_inst_dir $(which instrument-vmstat) --before"
fi

# Run the benchprog
do_ssh "$executable_path" --out-dir "$remote_tmpdir"

# Handle Instrumentation Teardown
if [ "$INSTRUMENT_VMSTAT" = true ]; then
    # shellcheck disable=SC2029
    do_ssh "KBN_INSTRUMENT_DIR=$remote_inst_dir $(which instrument-vmstat) --after"
    rsync -avz "$SSH_TARGET:$remote_inst_dir/" "$host_info_dir/instrumentation/"
fi

# Fetch benchmark results
local_tmpdir="${TMPDIR:-/tmp}/$(basename "$remote_tmpdir")"
rsync -avz "$SSH_TARGET:$remote_tmpdir/" "$local_tmpdir/"

# Import everything to Falba
# We include the instrumentation data by passing the $host_info_dir glob
falba import --test-name "$executable_name" --result-db "$FALBA_DB" "$local_tmpdir" "$host_info_dir"/**