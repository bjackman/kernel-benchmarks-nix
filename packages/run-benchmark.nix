{ pkgs, benchmarks }:
pkgs.writeShellApplication {
  name = "run-benchmark";
  runtimeInputs =
    (builtins.attrValues benchmarks)
    ++ (with pkgs; [
      # Some of these are available in a normal shell but need to be
      # specified explicitly so we can run this via systemd.
      docopts
      fio
      jq
      gawk # Required by docopts
      coreutils
      util-linux
    ]);
  text = builtins.readFile ../src/run-benchmark.sh;
  excludeShellChecks = [ "SC2154" ]; # Shellcheck can't tell ARGS_* is set.
  extraShellCheckFlags = [
    "--external-sources"
    "--source-path=${pkgs.docopts}/bin"
  ];
}
