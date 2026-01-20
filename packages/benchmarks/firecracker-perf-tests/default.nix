{ pkgs, lib, ... }:
let
  name = "firecracker-perf-tests";
in
# TODO: Not sure if callPackage is appropriate here of if wrap-benchmark should
# be a function passed into the package.
pkgs.callPackage ../../wrap-benchmark.nix {
  inherit name;
  rawBenchmark = pkgs.runCommand name { } ''
    mkdir -p $out/bin
    cp ${./firecracker-perf-tests.sh} $out/bin/firecracker-perf-tests
    chmod +x $out/bin/firecracker-perf-tests
  '';
}
