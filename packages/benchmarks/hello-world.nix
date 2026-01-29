# Dummy benchmark for poking around with the framework
{
  pkgs,
  lib,
  inputs,
  ...
}:
let
  name = "hello-world";
in
# TODO: Not sure if callPackage is appropriate here of if wrap-benchmark should
# be a function passed into the package.
pkgs.callPackage ../wrap-benchmark.nix {
  inherit name;
  rawBenchmark = pkgs.writeShellApplication {
    inherit name;
    text = "echo hello world";
  };
}

