# The microvm.nix runner is hard-coded to use the hostname as the path for the
# FC control socket.
# shellcheck disable=SC2034
FC_SOCK=nixos.sock

. lib.sh

# Take a snapshot. We'll spin up the VM and then just wait a second, dont'
# really care what the contents of the memory are for this usecase.
microvm-run &
runner_pid=$!

# Can shutdown via the API but there's no point - just kill it.
shutdown() {
    kill "$runner_pid"
}
trap shutdown EXIT

sleep 1
# Take a snapshot using the FC REST API.
fc_request PATCH '/vm' '{ "state": "Paused" }'
fc_request PUT '/snapshot/create' "{
    \"snapshot_type\": \"Full\",
    \"snapshot_path\": \"$PWD/vmstate\",
    \"mem_file_path\": \"$PWD/mem\"
}"

