{ pkgs, ... }:
let
  drv = pkgs.writeShellApplication {
    name = "vmstat";
    runtimeInputs = with pkgs; [
      coreutils
      gawk
    ];
    text = builtins.readFile ./vmstat.sh;

    passthru = rec {
      falba-parsers = pkgs.callPackage ./falba-parsers.nix { };
      falba-parsers-json = pkgs.writers.writeJSON "falba-parsers.json" {
        parsers = falba-parsers.parsers;
      };
    };
  };
in
drv
// {
  heavyCheck = pkgs.callPackage ./integration-test.nix {
    vmstat = drv;
  };
}
