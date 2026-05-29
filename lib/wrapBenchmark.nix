{
  pkgs,
  lib,
  inputs,
  self,
  ...
}:
# This function takes a base benchprog and turns it into a fully fledged
# benchprog package with test VM and sandbox check configurations.
{
  name,
  rawBenchmark,
  passthru ? { },
  # Modules that are required for the host the benchprog is running in.
  nixosModules ? [ ],
  requiresInternet ? false,
  worksInNixSandbox ? !requiresInternet,
  # Declarative integration test definitions
  integrationTests ? { },
}:
let
  # The standard wrapped host executable (handles --out-dir and exports OUT_DIR)
  wrappedProg = pkgs.writeShellApplication {
    name = "${name}";
    runtimeInputs = with pkgs; [ getopt ];
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

      if [ "$OUT_DIR" == "" ]; then
          OUT_DIR="$(mktemp -d)"
          echo "WARNING: --out-dir not set, using $OUT_DIR"
      fi

      if [ ! -d "$OUT_DIR" ] || [ ! -z "$(ls -A "$OUT_DIR")" ]; then
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

  # If the benchmark has NixOS modules, we assume it can only be tested in a VM.
  forceTestInVm = builtins.length nixosModules != 0;

  # Determine the test cases to configure.
  # For backwards compatibility, if no integrationTests are specified,
  # we auto-generate a default test case with no arguments.
  effectiveIntegrationTests =
    if integrationTests != { } then
      integrationTests
    else
      {
        default = {
          args = [ ];
        };
      };

  # Select which test case's VM runner to expose as the main .in-vm attribute
  defaultTestName =
    if effectiveIntegrationTests ? default then
      "default"
    else
      builtins.head (builtins.attrNames effectiveIntegrationTests);

  # Generate test closures and VM runners for each declared test case
  generateTests = lib.mapAttrs (
    testCaseName: testConfig:
    let
      testModule =
        { config, ... }:
        {
          systemd.services.kbn-guest = {
            script = ''
              set +e
              ${lib.getExe wrappedProg} --out-dir /mnt/kbn-output -- ${lib.escapeShellArgs testConfig.args}
              echo $? > /run/kbn-exit-code
            '';
            # Put all the stuff that a normal NixOS system has into the
            # systemd service environment, to make testing more practical.
            path = config.environment.systemPackages;
            serviceConfig = {
              Type = "oneshot";
              StandardOutput = "tty";
              StandardError = "tty";
              CacheDirectory = "kbn-guest";
              # Prevent the entire service from getting OOM-killed when the worker dies.
              OOMPolicy = "continue";
            };
            unitConfig = {
              SuccessAction = "poweroff";
              FailureAction = "poweroff";
            };
            after = [ "multi-user.target" ] ++ lib.optional requiresInternet "network-online.target";
            wants = [ "multi-user.target" ] ++ lib.optional requiresInternet "network-online.target";
          };
        };

      hostName = "testvm-${name}-${testCaseName}";
      nixosConfig = inputs.nixpkgs.lib.nixosSystem {
        system = pkgs.stdenv.hostPlatform.system;
        specialArgs = { inherit self; };
        modules = [
          ./vm-base-module.nix
          { networking.hostName = hostName; }
        ]
        ++ nixosModules
        ++ [ testModule ];
      };

      nixosRunner = nixosConfig.config.system.build.vm;
      testInVm = pkgs.writeShellApplication {
        name = "${name}-in-vm-${testCaseName}";
        runtimeInputs = [ pkgs.getopt ];
        text = ''
          usage() {
              cat <<EOF
          Usage: \$(basename "\$0") [OPTIONS]

          Options:
            -i, --interactive    Drop into a root shell instead of just running
                                 benchmark and shutting down.
            --vsock-cid          CID to assign for the guest for vsock connection.
                                 Default is 3.
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
      };

      test =
        if forceTestInVm then
          # Mark as impure VM test (Nix run target)
          pkgs.writeShellScriptBin "check-bench-${name}-${testCaseName}"
            "${lib.getExe testInVm} --vsock-cid=-1"
        else
          # Mark as sandboxed native check
          pkgs.runCommand "check-bench-${name}-${testCaseName}" { } ''
            export CACHE_DIRECTORY="$TMPDIR/kbn-cache"
            ${lib.getExe wrappedProg} -- ${lib.escapeShellArgs testConfig.args}
            touch $out
          '';
    in
    {
      in-vm = testInVm;
      inherit test;
    }
  ) effectiveIntegrationTests;

in
wrappedProg
// {
  inherit requiresInternet worksInNixSandbox;
  in-vm = generateTests.${defaultTestName}.in-vm;
  checks = if forceTestInVm then { } else lib.mapAttrs (n: v: v.test) generateTests;
  impureTests = if forceTestInVm then lib.mapAttrs (n: v: v.test) generateTests else { };
  vmRunners = lib.mapAttrs (n: v: v.in-vm) generateTests;
}
// passthru
