{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "instrument-uname";
  runtimeInputs = [ pkgs.coreutils ];
  text = ''
    exec uname --kernel-release > "$KBN_INSTRUMENT_DIR"/kernel_release.txt
  '';
  passthru = rec {
    falba-parsers.parsers.kernel_release = {
      type = "single_metric";
      artifact_regexp = "kernel_release.txt";
      fact = {
        name = "kernel_release";
        type = "string";
      };
    };
    falba-parsers-json = pkgs.writers.writeJSON "falba-parsers.json" {
      parsers = falba-parsers.parsers;
    };
  };
}
