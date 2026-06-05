#!/bin/bash

set -eu -o pipefail

#
# Stupid args boilerplate
#

FALBA_DB=.falba
COLLECT_FILES=()
DEFAULT_INSTRUMENTS=("nixos" "uname" "duration")
REQUESTED_INSTRUMENTS=()
DISABLED_INSTRUMENTS=()
SSH_PORT=22
DO_NIX_COPY=true
RUN_IN_VM=false
SSH_TARGET=""
BENCHPROG=""
STRESSOR=""

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS] [-- BENCHPROG_ARGS]

Options:
  -t, --target TARGET     [Required] The target machine to connect to via SSH (e.g., user@host).
  -b, --benchprog BENCH   [Required] The benchmark to run (either a built-in name from the registry or a Nix flakeref).
  -d, --falba-db DIR      [Required] Path to an existing Falba database directory.
  -c, --collect FILE      Collect specified remote file into the host info directory. Can be passed multiple times.
  --instruments INSTR     Specify instruments to execute before and after the benchmark. Can be passed multiple times.
                          Default instruments: nixos, uname.
  --disable-instrument INS Disable an instrument. Can be passed multiple times.
  --ssh-port PORT         Specify the SSH port to use.
  --no-copy               Skip executing 'nix copy' to push packages to the target.
  -v, --in-vm             Run the benchmark inside a VM (only supported for built-in benchmarks in the registry).
  --stressor STRESSOR     Specify a stressor to run in parallel with the benchmark.
  -h, --help              Display this help message and exit.

EOF

    echo -e "Built-in benchmarks:\n  "
    jq -r 'keys | .[]' < "$BENCHMARK_REGISTRY_JSON" | sed 's/^/  - /'
    echo -e "\nBuilt-in instruments:\n  "
    jq -r 'keys | .[]' < "$INSTRUMENT_REGISTRY_JSON" | sed 's/^/  - /'
    echo -e "\nBuilt-in stressors:\n  "
    jq -r 'keys | .[]' < "$STRESSOR_REGISTRY_JSON" | sed 's/^/  - /'
}

PARSED_ARGUMENTS=$(getopt -o d:c:vht:b: --long falba-db:,collect:,instruments:,disable-instrument:,ssh-port:,no-copy,in-vm,help,target:,benchprog:,stressor: -- "$@")

# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    echo "Error: Failed to parse arguments." >&2
    usage
    exit 1
fi

eval set -- "$PARSED_ARGUMENTS"
while true; do
    case "$1" in
        -t|--target)
            SSH_TARGET="$2"
            shift 2
            ;;
        -b|--benchprog)
            BENCHPROG="$2"
            shift 2
            ;;
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
            REQUESTED_INSTRUMENTS+=("$2")
            shift 2
            ;;
        --disable-instrument)
            DISABLED_INSTRUMENTS+=("$2")
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
        --stressor)
            STRESSOR="$2"
            shift 2
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

if [ "${SSH_TARGET:-}" == "" ]; then
    echo "Error: --target is required." >&2
    usage
    exit 1
fi

if [ "${BENCHPROG:-}" == "" ]; then
    echo "Error: --benchprog is required." >&2
    usage
    exit 1
fi

if [ "$FALBA_DB" == "" ] || [ ! -d "$FALBA_DB" ]; then
    echo "--falba-db must point to an existing Falba database."
    echo "If you intend to use $FALBA_DB, create that directory."
    exit 1
fi

if [ -n "$STRESSOR" ]; then
    stressor_executable="$(jq -r ".[\"$STRESSOR\"]" < "$STRESSOR_REGISTRY_JSON")"
    if [ "$stressor_executable" = "null" ] || [ -z "$stressor_executable" ]; then
        echo "Error: Unknown stressor $STRESSOR" >&2
        exit 1
    fi
fi

#
# End stupid args boilerplate
#

# Resolve instruments: default + requested - disabled
INSTRUMENTS=()
for inst in "${DEFAULT_INSTRUMENTS[@]}" "${REQUESTED_INSTRUMENTS[@]}"; do
    # Check if it is disabled
    disabled=false
    for dis in "${DISABLED_INSTRUMENTS[@]}"; do
        if [[ "$inst" == "$dis" ]]; then
            disabled=true
            break
        fi
    done
    if ! $disabled; then
        # Avoid duplicates
        duplicate=false
        for added in "${INSTRUMENTS[@]}"; do
            if [[ "$inst" == "$added" ]]; then
                duplicate=true
                break
            fi
        done
        if ! $duplicate; then
            INSTRUMENTS+=("$inst")
        fi
    fi
done

# SSH options to suppress host key checking and warnings, useful for transient VMs.
SSH_OPTS=(
    "-o" "StrictHostKeyChecking=no"
    "-o" "UserKnownHostsFile=/dev/null"
    "-o" "LogLevel=ERROR"
    "-o" "BatchMode=yes"
)
export NIX_SSHOPTS="${SSH_OPTS[*]}"

do_ssh() {
    local port_args
    if [ -n "$SSH_PORT" ]; then
        port_args=("-p" "$SSH_PORT")
    else
        port_args=()
    fi
    # shellcheck disable=SC2029
    ssh "${SSH_OPTS[@]}" "${port_args[@]}" "$SSH_TARGET" "$@"
}

do_scp_from() {
    local port_args
    if [ -n "$SSH_PORT" ]; then
        port_args=("-P" "$SSH_PORT")
    else
        port_args=()
    fi
    scp "${SSH_OPTS[@]}" "${port_args[@]}" "$SSH_TARGET:$1" "$2"
}

do_rsync_pull() {
    local rsync_ssh_opts=("${SSH_OPTS[@]}")
    if [ -n "$SSH_PORT" ]; then
        rsync_ssh_opts+=("-p" "$SSH_PORT")
    fi
    # shellcheck disable=SC2086
    rsync --rsync-path="$rsync_store_path" -e "ssh ${rsync_ssh_opts[*]}" -avz "$SSH_TARGET:$1" "$2"
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
if [ -n "$STRESSOR" ]; then
    to_install+=("$stressor_executable")
fi
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

# Collect additional requested files
# TODO: make this a parameterised instrument.
collected_files_dir="$(mktemp -d)"
for remote_file in "${COLLECT_FILES[@]}"; do
    do_scp_from "$remote_file" "$collected_files_dir/" || echo "Warning: Failed to collect $remote_file" >&2
done

# Setup Remote Directories
remote_tmpdir=$(do_ssh mktemp -d)

remote_stressor_dir=""
if [ -n "$STRESSOR" ]; then
    remote_stressor_dir=$(do_ssh mktemp -d)
    echo "Starting stressor $STRESSOR..."
    do_ssh "KBN_STRESSOR_DIR=$remote_stressor_dir $stressor_executable --start"
fi

# Handle Instrumentation Setup
remote_instr_dir="$(do_ssh mktemp -d)"
for executable in "${instr_executables[@]}"; do
    subdir="$remote_instr_dir/$(basename "$executable")"
    do_ssh "mkdir $subdir"
    do_ssh "KBN_INSTRUMENT_DIR=$subdir $executable --before"
done

# Run the benchprog
do_ssh "$bench_executable" --out-dir "$remote_tmpdir" -- "$@"

# Handle Instrumentation Teardown
for executable in "${instr_executables[@]}"; do
    subdir="$remote_instr_dir/$(basename "$executable")"
    do_ssh "KBN_INSTRUMENT_DIR=$subdir $executable --after"
done
do_rsync_pull "$remote_instr_dir/" "$collected_files_dir/instrumentation/"

# Stop and collect stressor
if [ -n "$STRESSOR" ]; then
    echo "Stopping stressor $STRESSOR..."
    do_ssh "KBN_STRESSOR_DIR=$remote_stressor_dir $stressor_executable --stop"
    mkdir -p "$collected_files_dir/stressors/$STRESSOR"
    do_rsync_pull "$remote_stressor_dir/" "$collected_files_dir/stressors/$STRESSOR/"
    do_ssh "rm -rf $remote_stressor_dir"
fi

# Fetch benchmark results
local_tmpdir="${TMPDIR:-/tmp}/$(basename "$remote_tmpdir")"
do_rsync_pull "$remote_tmpdir/" "$local_tmpdir/"

# Import everything to Falba
# We include the instrumentation data by passing the $collected_files_dir glob
falba import --test-name "$bench_name" --result-db "$FALBA_DB" "$local_tmpdir" "$collected_files_dir"/**