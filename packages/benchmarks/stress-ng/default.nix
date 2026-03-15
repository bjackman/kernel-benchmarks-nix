{
  pkgs,
  lib,
  inputs,
  wrapBenchmark,
  ...
}:
let
  name = "stress-ng";
in
wrapBenchmark {
  inherit name;
  rawBenchmark = pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = [ pkgs.stress-ng ];
    text = ''
      # TODO: Parameterize
      stress-ng --secretmem 0 -t 5s --metrics-brief --yaml "$OUT_DIR"/stress-ng-metrics-brief.yaml
    '';
  };
  passthru = rec {
    falba-parsers = pkgs.callPackage ./falba-parsers.nix { };
    falba-parsers-json = pkgs.writers.writeJSON "falba-parsers.json" {
      parsers = falba-parsers.parsers;
    };
  };
}
