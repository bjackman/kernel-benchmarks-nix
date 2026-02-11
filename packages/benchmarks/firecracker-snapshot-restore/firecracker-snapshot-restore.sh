# The microvm.nix runner is hard-coded to use the hostname as the path for the
# FC control socket.
FC_SOCK=nixos.sock

fc_request() {
    local verb="$1"
    local path="$2"
    local json="$3"

    curl --unix-socket "$FC_SOCK" -i -X "$verb" "http://localhost$path" \
    -H "Accept: application/json" -H "Content-Type: application/json" \
    -d "$json"
}

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
fc_request PUT '/snapshot/create' '{
    "snapshot_type": "Full",
    "snapshot_path": "/tmp/vmstate",
    "mem_file_path": "/tmp/mem"
}'

