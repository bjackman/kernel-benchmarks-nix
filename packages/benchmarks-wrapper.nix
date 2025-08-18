{ pkgs, bpftrace-scripts, run-benchmark }:
pkgs.writeShellApplication {
  name = "benchmarks-wrapper";
  runtimeInputs =
    [
      bpftrace-scripts
      run-benchmark
    ]
    ++ (with pkgs; [
      # Some of these are available in a normal shell but need to be
      # specified explicitly so we can run this via systemd.
      docopts
      gawk # Required by docopts
      coreutils
      util-linux
    ]);
  text = builtins.readFile ../src/benchmarks-wrapper.sh;
  excludeShellChecks = [ "SC2154" ]; # Shellcheck can't tell ARGS_* is set.
  extraShellCheckFlags = [
    "--external-sources"
    "--source-path=${pkgs.docopts}/bin"
  ];
}
