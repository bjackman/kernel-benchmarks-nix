{
  pkgs,
  lib,
  inputs,
  self,
}:
# This produces a version of the benchmark that gets run in a NixOS VM. The
# purposes of this are a) for benchmarking a host's performance as a
# hypervisor and b) for integration-testing the benchmark script.
# However, it's possible this is dumb: for a) maybe the idea of running random
# benchmarks in an arbitrary VMM is as silly way to benchmark. For b) maybe
# NixOS VM tests would be more suitable.{
{
  name,
  wrappedProg,
  nixosModules,
  requiresInternet,
  worksInNixSandbox,
}:
let
  hostName = "testvm-${name}";
  nixosConfig = inputs.nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    specialArgs = { inherit self; };
    modules = [
      ../vm-base-module.nix
      (
        { config, ... }:
        {
          networking.hostName = hostName;

          # As an easy way to be able to run it from the kernel cmdline, just
          # encode the benchmark into a systemd service. You can then run it
          # with systemd.unit=kbn-guest.service
          systemd.services.kbn-guest = {
            script = ''
              set +e
              ${lib.getExe wrappedProg} --out-dir /mnt/kbn-output
              echo $? > /run/kbn-exit-code
            '';
            # Put all the stuff that a normal NixOS system has into the
            # systemd service environment, to make testing more practical.
            # Use systemPackages instead of corePackages so that stuff
            # installed by the benchmark's NixOS module is also visible.
            path = config.environment.systemPackages;
            serviceConfig = {
              Type = "oneshot";
              StandardOutput = "tty";
              StandardError = "tty";
              CacheDirectory = "kbn-guest";
            };
            unitConfig = {
              SuccessAction = "poweroff";
              FailureAction = "poweroff";
            };
            after = [ "multi-user.target" ] ++ lib.optional requiresInternet "network-online.target";
            wants = [ "multi-user.target" ] ++ lib.optional requiresInternet "network-online.target";
          };
        }
      )
    ]
    ++ nixosModules;
  };
  # This is the "official" entry point for running NixOS as a QEMU guest, we'll
  # wrap this.
  nixosRunner = nixosConfig.config.system.build.vm;
in
pkgs.writeShellApplication {
  name = "${name}-in-vm";
  runtimeInputs = [ pkgs.getopt ];
  text = ''
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
    ${nixosRunner}/bin/run-${hostName}-vm
  '';
  passthru = { inherit nixosConfig requiresInternet worksInNixSandbox; };
}
