{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  name = "firecracker-perf-tests";
in
# TODO: Not sure if callPackage is appropriate here of if wrap-benchmark should
# be a function passed into the package.
pkgs.callPackage ../../wrap-benchmark.nix {
  inherit name;
  rawBenchmark = pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = with pkgs; [ git ];
    text = builtins.readFile ./firecracker-perf-tests.sh;
    runtimeEnv.FIRECRACKER_REV = inputs.firecracker.rev;
  };
}
