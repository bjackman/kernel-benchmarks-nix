# Dummy benchmark for poking around with the framework
{
  pkgs,
  lib,
  inputs,
  wrapBenchmark,
  ...
}:
let
  name = "hello-world";
in
wrapBenchmark {
  inherit name;
  rawBenchmark = pkgs.writeShellApplication {
    inherit name;
    text = "echo hello world";
  };
}
