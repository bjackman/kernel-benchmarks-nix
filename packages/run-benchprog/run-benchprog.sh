#!/bin/bash

set -eu -o pipefail

#
# Stupid args boilerplate
#

FALBA_DB=.falba
COLLECT_FILES=()
INSTRUMENTS=()
SSH_PORT=22
DO_NIX_COPY=true
RUN_IN_VM=false

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] SSH_TARGET BENCHPROG

Arguments:
  SSH_TARGET              The target machine to connect to via SSH (e.g., user@host).
  BENCHPROG               The benchmark to run (either a built-in name from the registry or a Nix flakeref).

Options:
  -d, --falba-db DIR      [Required] Path to an existing Falba database directory.
  -c, --collect FILE      Collect specified remote file into the host info directory. Can be passed multiple times.
  --instruments INSTR     Specify instruments to execute before and after the benchmark. Can be passed multiple times.
  --ssh-port PORT         Specify the SSH port to use.
  --no-copy               Skip executing 'nix copy' to push packages to the target.
  -v, --in-vm             Run the benchmark inside a VM (only supported for built-in benchmarks in the registry).
  -h, --help              Display this help message and exit.

EOF

    echo -e "Built-in benchmarks:\n  "
    jq -r 'keys | .[]' < "$BENCHMARK_REGISTRY_JSON" | sed 's/^/  - /'
    echo -e "\nBuilt-in instruments:\n  "
    jq -r 'keys | .[]' < "$INSTRUMENT_REGISTRY_JSON" | sed 's/^/  - /'
}

PARSED_ARGUMENTS=$(getopt -o d:c:vh --long falba-db:,collect:,instruments:,ssh-port:,no-copy,in-vm,help -- "$@")

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
        # TODO: This should be implemented via the instrument mechanism.
        -c|--collect)
            COLLECT_FILES+=("$2")
            shift 2
            ;;
        --instruments)
            INSTRUMENTS+=("$2")
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
        -v|--in-vm)
            RUN_IN_VM=true
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


# Figure out the command to run.
# Is $BENCHPROG in the JSON registry? jq should either produce "null"
# or a JSON object with the native and in-vm variants of the benchmark.
benchmark_json="$(jq ".[\"$BENCHPROG\"]" < "$BENCHMARK_REGISTRY_JSON")"
if [[ "$benchmark_json" != "null" ]]; then
    echo "Using built-in benchmark $BENCHPROG"
    if "$RUN_IN_VM"; then
        jq='.["in-vm"]'
    else
        jq='.native'
    fi
    bench_executable="$(echo "$benchmark_json" | jq -er "$jq")"
    bench_name="$BENCHPROG"
else
    echo "Assuming $BENCHPROG is a flakeref"
    if "$RUN_IN_VM"; then
        echo "--in-vm is only supported for built-in benchmarks."
        echo "If the benchmark is built via KBN's infrastructure you may be"
        echo "able to append .in-vm to the flakeref to run it in a VM."
        exit 1
    fi
    bench_executable=$(nix eval --raw "$BENCHPROG.meta.mainProgram")
fi

rsync_store_path="$(realpath "$(which rsync)")"
to_install=("$bench_executable" "$rsync_store_path")
instr_executables=()
for instr in "${INSTRUMENTS[@]}"; do
    executable=$(jq -er ".[\"$instr\"]" < "$INSTRUMENT_REGISTRY_JSON")
    instr_executables+=("$executable")
    to_install+=("$executable")
done

if "$DO_NIX_COPY"; then
    for pkg in "${to_install[@]}"; do
        nix copy --no-check-sigs --to ssh-ng://"$SSH_TARGET" "$pkg"
    done
fi

# Fetch generic target data
# TODO: Immplement this as an instrument.
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

# Setup Remote Directories
remote_tmpdir=$(do_ssh mktemp -d)

# Handle Instrumentation Setup
remote_instr_dir="$(do_ssh mktemp -d)"
for executable in "${instr_executables[@]}"; do
    subdir="$remote_instr_dir/$(basename "$executable")"
    do_ssh "mkdir $subdir"
    do_ssh "KBN_INSTRUMENT_DIR=$subdir $executable --before"
done

# Run the benchprog
do_ssh "$bench_executable" --out-dir "$remote_tmpdir"

# Handle Instrumentation Teardown
for executable in "${instr_executables[@]}"; do
    do_ssh "KBN_INSTRUMENT_DIR=$subdir $executable --after"
done
rsync --rsync-path="$rsync_store_path" -avz "$SSH_TARGET:$remote_instr_dir/" "$host_info_dir/instrumentation/"

# Fetch benchmark results
local_tmpdir="${TMPDIR:-/tmp}/$(basename "$remote_tmpdir")"
rsync --rsync-path="$rsync_store_path" -avz "$SSH_TARGET:$remote_tmpdir/" "$local_tmpdir/"

# Import everything to Falba
# We include the instrumentation data by passing the $host_info_dir glob
falba import --test-name "$bench_name" --result-db "$FALBA_DB" "$local_tmpdir" "$host_info_dir"/**