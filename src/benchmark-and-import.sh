#!/bin/bash
#
# Runs benchmarks-wrapper on a remote host, fetches its results, and imports
# them into the FALBA database.
#
# Usage:
#     benchmark-and-import [options] --benchmark <benchmark> <host>
#     benchmark-and-import --help
#
# Options:
#     -h --help                Show this screen.
#     --instrument             Run instrumentation for these benchmarks
#     --result-db RESULT_DB    Magic result database to upload to [default: ./results].
#     --benchmark <benchmark>  Either 'fio' or 'compile-kernel'
#     --guest                  Run the benchmark in a guest instead of in the host
#     <host>                   Hostname/IP of target. All other options (port, user) hardcoded.

set -eu -o pipefail

source docopts.sh --auto -G "$@"

USER=brendan  # good user, good 2 hard code

function do_ssh() {
    # shellcheck disable=SC2029
    ssh "$USER@$ARGS_host" "$@"
}

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
scp -r "$USER@$ARGS_host":"$REMOTE_RESULTS_DIR/*" "$local_results_dir"

if "$ARGS_guest"; then
    test_name="$ARGS_benchmark"_guest
else
    test_name="$ARGS_benchmark"_host
fi
falba import --test-name "$test_name" "$local_results_dir"/*