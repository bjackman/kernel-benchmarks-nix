{ pkgs, ... }:
let
  drv = pkgs.writeShellApplication {
    name = "duration";
    runtimeInputs = with pkgs; [
      coreutils
    ];
    text = builtins.readFile ./duration.sh;

    passthru = rec {
      falba-parsers.parsers.duration = {
        type = "single_metric";
        artifact_regexp = "instrumentation/duration/duration.txt";
        metric = {
          name = "duration_us";
          type = "int";
          unit = "us";
        };
      };
      falba-parsers-json = pkgs.writers.writeJSON "falba-parsers.json" {
        parsers = falba-parsers.parsers;
      };
    };
  };
in
drv
