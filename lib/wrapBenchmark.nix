{
  pkgs,
  lib,
  inputs,
  self,
  ...
}:
# This function takes a base benchprog (TODO: document exactly what that means)
# and turns it into a fully fledged benchprog package.
{
  name,
  rawBenchmark,
  passthru ? { },
  # Modules that are required for the host the benchprog is running in.
  nixosModules ? [ ],
  requiresInternet ? false,
}:
let
  wrappedProg = pkgs.writeShellApplication {
    name = "${name}-wrapped";
    text = ''
      OUT_DIR=

      PARSED_ARGUMENTS=$(getopt -o o: --long out-dir: -- "$@")

      # shellcheck disable=SC2181
      if [ $? -ne 0 ]; then
          echo "Error: Failed to parse arguments." >&2
          usage
          exit 1
      fi
      eval set -- "$PARSED_ARGUMENTS"
      while true; do
          case "$1" in
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
                  echo "Unexpected argument, script bug? $1" >&2
                  exit 1
                  ;;
          esac
      done

      if [ "$OUT_DIR" == "" ] || [ ! -d "$OUT_DIR" ] || [ ! -z "$(ls -A "$OUT_DIR")" ]; then
          echo "--out-dir must point to an empty directory."
          exit 1
      fi

      export OUT_DIR

      BASE_CACHE="''${CACHE_DIRECTORY:-''${XDG_CACHE_HOME:-''${HOME:+$HOME/.cache}}}"
      export KBN_CACHE_DIR="$BASE_CACHE/kbn/${name}"
      mkdir -p "$KBN_CACHE_DIR"
      exec "${lib.getExe rawBenchmark}" "$@"
    '';
  };
in
wrappedProg
// {
  # This produces a version of the benchmark that gets run in a NixOS VM. The
  # purposes of this are a) for benchmarking a host's performance as a
  # hypervisor and b) for integration-testing the benchmark script.
  in-vm =
    let
      hostName = "testvm-${name}";
      nixosConfig = inputs.nixpkgs.lib.nixosSystem {
        system = pkgs.stdenv.hostPlatform.system;
        specialArgs = { inherit self; };
        modules =
          let
            # I/O port that will be used for the isa-debug-exit device. I don't know
            # how arbitrary this value is, I got it from Gemini who I suspect is
            # cargo-culting from https://os.phil-opp.com/testing/
            qemuExitPortHex = "0xf4";
          in
          [
            (
              { pkgs, config, ... }:
              rec {
                networking.hostName = hostName;
                virtualisation.vmVariant = {
                  virtualisation = {
                    graphics = false;
                    qemu.options = [
                      # This BIOS doesn't mess up the terminal and is apparently faster.
                      "-bios"
                      "qboot.rom"
                      "-device"
                      "isa-debug-exit,iobase=${qemuExitPortHex},iosize=0x04"
                    ];
                    # Tell the VM runner script that it should mount a directory on the
                    # host, named in the environment variable, to /mnt/kbn-output. That
                    # variable must point to a directory. This is coupled with the script
                    # content below.
                    sharedDirectories = {
                      kbn-output = {
                        source = "$KBN_OUTPUT_HOST";
                        target = "/mnt/kbn-output";
                      };
                    };
                    # Attempt to ensure there's space left over in the rootfs (which
                    # may be where /tmp is).
                    diskSize = lib.mkDefault (2 * 1024); # Megabytes
                    # This seems to speed up boot a bit.
                    cores = 8;
                    memorySize = lib.mkDefault (6 * 1024); # Megabytes
                  };
                };
                boot.tmp.useTmpfs = true;
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
                  onSuccess = [ "poweroff.target" ];
                  onFailure = [ "poweroff.target" ];
                  after = [ "multi-user.target" ] ++ lib.optional requiresInternet "network-online.target";
                  wants = [ "multi-user.target" ] ++ lib.optional requiresInternet "network-online.target";
                };
                # This service does the forwarding of the benchmark exit code to
                # the QEMU hypervisor. I think the proper way to do this would be
                # /usr/lib/systemd/systemd-shutdown/ but I couldn't get that
                # working so whatever.
                systemd.services.kbn-shutdown-exit = {
                  unitConfig.DefaultDependencies = false;
                  script = ''
                    set +x
                    if [ -f /run/kbn-exit-code ]; then
                      CODE=$(cat /run/kbn-exit-code)
                    else
                      echo "/run/kbn-exit-code missing"
                      CODE=213
                    fi
                    if [ "$CODE" -ne 0 ]; then
                      # Writing the value v to the isa-debug-exit port will cause QEMU to
                      # immediately exit with the exit code `v << 1 | 1`.
                      ${pkgs.ioport}/bin/outb -- ${qemuExitPortHex} $(( CODE - 1 ))
                    fi
                  '';
                  serviceConfig = {
                    Type = "oneshot";
                    StandardOutput = "tty";
                    StandardError = "tty";
                  };
                  after = [ "shutdown.target" ];
                  before = [ "poweroff.target" ];
                  wantedBy = [ "poweroff.target" ];
                };
                # Don't bother storing logs to disk, that seems like it will just
                # occasionally lead to unnecessary slowdowns for log rotation and
                # stuff.
                services.journald.storage = "volatile";

                services.getty.autologinUser = "root";
                services.openssh = {
                  enable = true;
                  settings = {
                    PermitEmptyPasswords = "yes";
                    PermitRootLogin = "yes";
                  };
                };
                users.users.root.initialHashedPassword = "";
                security.pam.services.sshd.allowNullPassword = true;
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

        PARSED_ARGUMENTS=$(getopt -o i --long interactive,vsock-cid: -- "$@")

        # shellcheck disable=SC2181
        if [ $? -ne 0 ]; then
          echo "Error: Failed to parse arguments." >&2
          usage
          exit 1
        fi
        eval set -- "$PARSED_ARGUMENTS"

        INTERACTIVE=false
        VSOCK_CID=3

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
          export QEMU_KERNEL_PARAMS="systemd.unit=kbn-guest.service"
        fi

        if [[ "$VSOCK_CID" != -1 ]]; then
          QEMU_OPTS="$QEMU_OPTS -device vhost-vsock-pci,guest-cid=$VSOCK_CID"
        fi

        # TODO: Set this properly
        export KBN_OUTPUT_HOST=/tmp/kbn_guest_output
        export QEMU_OPTS
        mkdir -p "$KBN_OUTPUT_HOST"
        ${nixosRunner}/bin/run-${hostName}-vm
      '';
      passthru = { inherit nixosConfig; };
    };
}
// passthru
