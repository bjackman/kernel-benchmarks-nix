#!/bin/bash
#
# Usage:
#     benchmark-configs [options] --benchmark <benchmark> <host> <variant>...
#     benchmark-configs --help
#
# Options:
#     -h --help                      Show this screen.
#     --instrument                   Run instrumentation for these benchmarks
#     --result-db <falba-db>         Falba result database to upload to [default: ./results].
#     --config-deployer <deployer>   Script for deploying the config. Defaults
#                                    to one that does this over SSH with
#                                    nixos-rebuild. [default: deploy-config]
#     --benchmark <benchmark>        Either 'fio' or 'compile-kernel'
#     --guest                        Run the benchmark in a guest instead of in the host
#     <host>                         Hostname/IP of target. All other options (port, user) hardcoded.
#     <flakerefs>                    Flake references pointing to NixOS configurations to benchmark.

NIX_SSHOPTS=${NIX_SSHOPTS:-}

set -eu -o pipefail

source docopts.sh --auto -G "$@"

USER=brendan  # TODO: UM LOL THIS SUCKS SO MUCH

function do_ssh() {
    ssh "$USER@$ARGS_host" "$@"
}

for flakeref in "${ARGS_flakeref[@]}"; do
    "$ARGS_config_deployer" "$ARGS_host" "$flakeref"

    # Run the benchmarks
    REMOTE_RESULTS_DIR=/tmp/benchmark-results
    # shellcheck disable=SC2029
    do_ssh "rm -rf $REMOTE_RESULTS_DIR; mkdir $REMOTE_RESULTS_DIR"
    cmd="benchmarks-wrapper --out-dir $REMOTE_RESULTS_DIR $ARGS_benchmark"
    if "$ARGS_instrument"; then
        cmd="$cmd --instrument"
    fi
    if "$ARGS_guest"; then
        cmd="$cmd --guest"
    fi
    do_ssh "$cmd"

    # Fetch the results
    local_results_dir=$(mktemp -d)
    scp -P "$ARGS_ssh_port" -r "$USER@$ARGS_host":"$REMOTE_RESULTS_DIR/*" "$local_results_dir"

    # Hash them and store them in the format required by my cool secret
    # benchmarking result schema: $name:$hash.
    # This will import to the default Falba DB location i.e. ./results/
    if "$ARGS_guest"; then
        test_name="$ARGS_benchmark"_guest
    else
        test_name="$ARGS_benchmark"_host
    fi
    falba import --test-name "$test_name" "$local_results_dir"/*
done