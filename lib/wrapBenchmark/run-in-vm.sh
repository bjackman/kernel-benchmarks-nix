# Expects:
# - KBN_VM_RUNNER

usage() {
    cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Options:
  -i, --interactive    Drop into a root shell instead of just running
                       benchmark and shutting down.
  --vsock-cid          CID to assign for the guest for vsock connection.
                       Default is 3 - this is a global resource so if you're
                       running multiple instances at once you'll get errors.
  -b, --shutdown       Just boot and then immediately shut down again.
  -h, --help           Display this help message and exit.

EOF
}

PARSED_ARGUMENTS=$(getopt -o io: --long interactive,vsock-cid:,out-dir: -- "$@")

# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
  echo "Error: Failed to parse arguments." >&2
  usage
  exit 1
fi
eval set -- "$PARSED_ARGUMENTS"

INTERACTIVE=false
VSOCK_CID=3
OUT_DIR=""

while true; do
    case "$1" in
        -i|--interactive)
          INTERACTIVE=true
          shift
          ;;
        --vsock-cid)
          VSOCK_CID="$2"
          shift 2
          ;;
        -o|--out-dir)
          OUT_DIR="$2"
          shift 2
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
          echo "Unexpected argument $1" >&2
          exit 1
          ;;
    esac
done

QEMU_OPTS=

# Normal mode is just to run the benchmark via the kbn-guest systemd
# service then shut down. Otherwise, we'll rely on autologin to give us
# a root shell which can be used to poke around in the guest for
# debugging.
if ! "$INTERACTIVE"; then
  export QEMU_KERNEL_PARAMS="systemd.unit=kbn-guest.service systemd.mask=serial-getty@ttyS0.service systemd.mask=getty@tty1.service"
fi

if [[ "$VSOCK_CID" != -1 ]]; then
  QEMU_OPTS="$QEMU_OPTS -device vhost-vsock-pci,guest-cid=$VSOCK_CID"
fi

if [ "$OUT_DIR" == "" ]; then
  OUT_DIR="$(mktemp -d)"
  echo "WARNING: --out-dir not set, using $OUT_DIR"
fi

if [ ! -d "$OUT_DIR" ] || [ ! -z "$(ls -A "$OUT_DIR")" ]; then
  echo "--out-dir must point to an empty directory."
  exit 1
fi

export KBN_OUTPUT_HOST="$OUT_DIR"
export QEMU_OPTS
exec "$KBN_VM_RUNNER"
