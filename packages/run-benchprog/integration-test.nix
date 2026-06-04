# Slop-coded integration test. This used to be a NixOS test but it turns out that
# running this in the Nix build sandbox on non-NixOS is broken, it requires
# /dev/kvm to be world-readable or it falls back to TCG which is unusably slow.
{
  pkgs,
  lib,
  run-benchprog,
  hello-world-in-vm,
  ...
}:
pkgs.writeShellApplication {
  name = "run-benchprog-integration-test";
  runtimeInputs = with pkgs; [
    netcat-openbsd
    python3 # for dynamic port allocation
  ];
  text = ''
    set -eu -o pipefail

    TMP_DIR=$(mktemp -d)
    VM_PID=""
    SUCCESS=false

    cleanup() {
        echo "Cleaning up..."
        if [ -n "$VM_PID" ]; then
            echo "Killing VM (PID $VM_PID)..."
            kill "$VM_PID" || true
            wait "$VM_PID" 2>/dev/null || true
        fi
        if ! "$SUCCESS" && [ -f "$TMP_DIR/vm.log" ]; then
            echo "--- VM Log ---"
            cat "$TMP_DIR/vm.log"
            echo "--------------"
        fi
        rm -rf "$TMP_DIR"
    }
    trap cleanup EXIT

    # Find a free port on host
    PORT=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1]); s.close()')
    echo "Using host port $PORT for SSH forwarding"

    # Start VM.
    export KBN_OUTPUT_HOST="$TMP_DIR"

    echo "Starting target VM..."
    (
        cd "$TMP_DIR"
        export QEMU_NET_OPTS="hostfwd=tcp:127.0.0.1:$PORT-:22"
        ${lib.getExe hello-world-in-vm} --interactive --vsock-cid=-1 > vm.log 2>&1 &
        echo $! > vm.pid
    )
    VM_PID=$(cat "$TMP_DIR/vm.pid")

    echo "Waiting for target VM SSH to be ready on port $PORT..."
    timeout=60
    while ! nc -z 127.0.0.1 "$PORT"; do
        sleep 1
        timeout=$((timeout - 1))
        if [ $timeout -le 0 ]; then
            echo "Timed out waiting for VM to boot"
            exit 1
        fi
    done
    echo "Target VM SSH is ready."

    mkdir -p "$TMP_DIR/falba-db"

    echo "Running run-benchprog..."
    ${lib.getExe run-benchprog} \
        --falba-db "$TMP_DIR/falba-db" \
        --instruments vmstat \
        --instruments nixos \
        --no-copy \
        --target root@127.0.0.1 \
        --ssh-port "$PORT" \
        --benchprog hello-world

    # Verify results
    echo "Verifying results..."
    if ! ls "$TMP_DIR"/falba-db/hello-world:*/artifacts/instrumentation/vmstat/before >/dev/null 2>&1; then
        echo "Verification failed: vmstat before artifact missing"
        exit 1
    fi
    if ! ls "$TMP_DIR"/falba-db/hello-world:*/artifacts/instrumentation/vmstat/after >/dev/null 2>&1; then
        echo "Verification failed: vmstat after artifact missing"
        exit 1
    fi
    if ! ls "$TMP_DIR"/falba-db/hello-world:*/artifacts/instrumentation/nixos/nixos-version.json >/dev/null 2>&1; then
        echo "Verification failed: nixos-version.json missing"
        exit 1
    fi

    SUCCESS=true
    echo "Integration test passed successfully!"
  '';
}
