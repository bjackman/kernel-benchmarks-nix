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
  worksInNixSandbox ? !requiresInternet,
}:
let
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

  inVmHelper = pkgs.callPackage ./in-vm.nix { inherit self inputs; };

  in-vm = inVmHelper {
    inherit
      name
      wrappedProg
      nixosModules
      requiresInternet
      worksInNixSandbox
      ;
  };

  # If it has NixOS modules then we assume it can only be tested in a VM. If
  # needed we can also add a flag to let benchmarks explicitly mark
  # themselves as needing a VM for other reasons (e.g. needing root).
  forceTestInVm = builtins.length nixosModules != 0;
  testScript =
    if forceTestInVm then
      # Disable vsock since that doesn't work in the Nix sandbox.
      "${lib.getExe in-vm} --vsock-cid=-1"
    else
      lib.getExe wrappedProg;
in
wrappedProg
// rec {
  inherit requiresInternet worksInNixSandbox in-vm;
  # Provides a check to actually run the benchmark - this is not included in the
  # checkPhase of the main derviation as it's probably slow; instead this lets
  # it be offloaded into the flake check output. This is null if the benchmark
  # can't be run in the Nix build sandbox.
  heavyCheck =
    # KVM is not available in the Nix sandbox so QEMU will fall back to TCG and
    # be unusably slow. So in that case we just consider it impure.
    # (You can set requiredSystemFeatures = [ "kvm" ] but this doesn't seem to
    # work, AI says you would need to add the Nix build users to the kvm group
    # so basically that functionality does not work.
    if forceTestInVm then
      null
    else
      pkgs.runCommand "check-bench-${name}" { } ''
        export CACHE_DIRECTORY="$TMPDIR/kbn-cache"
        ${testScript}
        touch $out
      '';
  # If heavyCheck was null then impureCheck can be used instead. Instead of
  # being a check (i.e. something you build, if it builds the test passed) this
  # is a binary that you run (via nix run).
  impureTest =
    if heavyCheck == null then pkgs.writeShellScriptBin "check-bench-${name}" testScript else null;
}
// passthru
