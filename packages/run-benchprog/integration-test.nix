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

    # Test Case 1: Default instruments (nixos, uname) should be run by default
    mkdir -p "$TMP_DIR/falba-db-default"
    echo "Running Test Case 1: Default instruments..."
    ${lib.getExe run-benchprog} \
        --falba-db "$TMP_DIR/falba-db-default" \
        --no-copy \
        --target root@127.0.0.1 \
        --ssh-port "$PORT" \
        --benchprog hello-world

    echo "Verifying Test Case 1..."
    if ! ls "$TMP_DIR"/falba-db-default/hello-world:*/artifacts/instrumentation/nixos/nixos-version.json >/dev/null 2>&1; then
        echo "Verification failed: nixos-version.json missing"
        exit 1
    fi
    if ! ls "$TMP_DIR"/falba-db-default/hello-world:*/artifacts/instrumentation/instrument-uname/kernel_release.txt >/dev/null 2>&1; then
        echo "Verification failed: kernel_release.txt missing"
        exit 1
    fi
    if ! ls "$TMP_DIR"/falba-db-default/hello-world:*/artifacts/instrumentation/duration/duration.txt >/dev/null 2>&1; then
        echo "Verification failed: duration.txt missing"
        exit 1
    fi
    if ls -d "$TMP_DIR"/falba-db-default/hello-world:*/artifacts/instrumentation/vmstat >/dev/null 2>&1; then
        echo "Verification failed: vmstat should not have run"
        exit 1
    fi

    # Test Case 2: Disable uname, nixos should still run
    mkdir -p "$TMP_DIR/falba-db-disable-uname"
    echo "Running Test Case 2: Disable uname..."
    ${lib.getExe run-benchprog} \
        --falba-db "$TMP_DIR/falba-db-disable-uname" \
        --disable-instrument uname \
        --no-copy \
        --target root@127.0.0.1 \
        --ssh-port "$PORT" \
        --benchprog hello-world

    echo "Verifying Test Case 2..."
    if ! ls "$TMP_DIR"/falba-db-disable-uname/hello-world:*/artifacts/instrumentation/nixos/nixos-version.json >/dev/null 2>&1; then
        echo "Verification failed: nixos-version.json missing"
        exit 1
    fi
    if ls -d "$TMP_DIR"/falba-db-disable-uname/hello-world:*/artifacts/instrumentation/instrument-uname >/dev/null 2>&1; then
        echo "Verification failed: uname should not have run"
        exit 1
    fi

    # Test Case 3: Disable all defaults, enable vmstat
    mkdir -p "$TMP_DIR/falba-db-disable-all"
    echo "Running Test Case 3: Disable all defaults, enable vmstat..."
    ${lib.getExe run-benchprog} \
        --falba-db "$TMP_DIR/falba-db-disable-all" \
        --disable-instrument nixos \
        --disable-instrument uname \
        --disable-instrument duration \
        --instruments vmstat \
        --no-copy \
        --target root@127.0.0.1 \
        --ssh-port "$PORT" \
        --benchprog hello-world

    echo "Verifying Test Case 3..."
    if ! ls "$TMP_DIR"/falba-db-disable-all/hello-world:*/artifacts/instrumentation/vmstat/before >/dev/null 2>&1; then
        echo "Verification failed: vmstat before artifact missing"
        exit 1
    fi
    if ! ls "$TMP_DIR"/falba-db-disable-all/hello-world:*/artifacts/instrumentation/vmstat/after >/dev/null 2>&1; then
        echo "Verification failed: vmstat after artifact missing"
        exit 1
    fi
    if ls -d "$TMP_DIR"/falba-db-disable-all/hello-world:*/artifacts/instrumentation/nixos >/dev/null 2>&1; then
        echo "Verification failed: nixos should not have run"
        exit 1
    fi
    if ls -d "$TMP_DIR"/falba-db-disable-all/hello-world:*/artifacts/instrumentation/instrument-uname >/dev/null 2>&1; then
        echo "Verification failed: uname should not have run"
        exit 1
    fi
    if ls -d "$TMP_DIR"/falba-db-disable-all/hello-world:*/artifacts/instrumentation/duration >/dev/null 2>&1; then
        echo "Verification failed: duration should not have run"
        exit 1
    fi

    # Test Case 4: Run with stressor
    mkdir -p "$TMP_DIR/falba-db-stressor"
    echo "Running Test Case 4: Run with stressor..."
    ${lib.getExe run-benchprog} \
        --falba-db "$TMP_DIR/falba-db-stressor" \
        --no-copy \
        --target root@127.0.0.1 \
        --ssh-port "$PORT" \
        --benchprog hello-world \
        --stressor secretmem

    echo "Verifying Test Case 4..."
    if ! ls "$TMP_DIR"/falba-db-stressor/hello-world:*/artifacts/stressors/secretmem/status.json >/dev/null 2>&1; then
        echo "Verification failed: status.json missing"
        exit 1
    fi
    status_content=$(cat "$TMP_DIR"/falba-db-stressor/hello-world:*/artifacts/stressors/secretmem/status.json)
    if [ "$status_content" != '{"stressed": true}' ]; then
        echo "Verification failed: status.json content is wrong: $status_content"
        exit 1
    fi

    SUCCESS=true
    echo "Integration test passed successfully!"
  '';
}
