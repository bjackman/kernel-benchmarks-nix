if [[ ! -f ./mem ]]; then
    echo "Generating snapshot"
    firecracker-gen-snapshot
fi
if [[ ! -f ./mem ]]; then
    echo "firecracker-gen-snapshot didn't generate ./mem file"
fi
if [[ ! -f ./vmstate ]]; then
    echo "firecracker-gen-snapshot didn't generate ./vmstate file"
fi

fc_pid=
uffd_pid=
cleanup() {
    if [[ "$fc_pid" != "" ]]; then
        kill "$fc_pid"
    fi
    if [[ "$uffd_pid" != "" ]]; then
        kill "$uffd_pid"
    fi
}
trap cleanup EXIT

. lib.sh

echo "Starting Firecracker daemon"

TMPDIR=$(mktemp -d)
# shellcheck disable=SC1091
FC_SOCK="$TMPDIR/fc.sock"
firecracker --no-seccomp --api-sock "$FC_SOCK" &
fc_pid=$!

echo "Starting userfaultfd daemon"

# We assume that "mem" is in the CWD from the gen-snapshot run.
# uffd_fault_all_handler comes from the firecracker code, it's an example.
UFFD_SOCK="$TMPDIR/uffd.sock"
uffd_fault_all_handler "$UFFD_SOCK" ./mem &
uffd_pid=$!

echo "Loading snapshot"

# And this assumes that "vmstate" is in the CWD also from the gen-snapshot run.
fc_request PUT '/snapshot/load' "{
    \"snapshot_path\": \"$PWD/vmstate\",
    \"mem_backend\": {
        \"backend_path\": \"$UFFD_SOCK\",
        \"backend_type\": \"Uffd\"
    },
    \"enable_diff_snapshots\": false,
    \"resume_vm\": true
}"