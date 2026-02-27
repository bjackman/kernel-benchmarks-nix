{
  pkgs,
  lib,
  inputs,
  wrapBenchmark,
  ...
}:
let
  name = "firecracker-perf-tests";
in
wrapBenchmark {
  inherit name;
  rawBenchmark = pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = with pkgs; [
      git
      getopt
      awscli2
    ];
    text = builtins.readFile ./firecracker-perf-tests.sh;
    runtimeEnv.FIRECRACKER_REV = inputs.firecracker.rev;
  };
  nixosModules = [ ./module.nix ];
  passthru = rec {
    falba-parsers = import ./falba-parsers.nix;
    falba-parsers-json = pkgs.writers.writeJSON "falba-parsers.json" falba-parsers;
  };
  requiresInternet = true;
}
