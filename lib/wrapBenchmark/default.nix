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
  # raw benchmark executable expects to run as root. This means integration
  # tests will be run in a VM, and the wrapper will run it via sudo.
  requiresRoot ? false,
  worksInNixSandbox ? (!requiresInternet && !requiresRoot),
}:
let
  wrappedProg = pkgs.writeShellApplication {
    name = "${name}";
    runtimeInputs = with pkgs; [
      getopt
      sudo
    ];
    runtimeEnv = {
      KBN_BENCH_NAME = name;
      KBN_RAW_BENCH_EXE = lib.getExe rawBenchmark;
      # Just use sudo unconditionally if we need root, assume sudoing is
      # harmless if already root. Might want to change this if we want to run on
      # weird platforms one day.
      KBN_USE_SUDO = lib.boolToString requiresRoot;
    };
    text = builtins.readFile ./wrapper.sh;
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
  forceTestInVm = requiresRoot || builtins.length nixosModules != 0;
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
