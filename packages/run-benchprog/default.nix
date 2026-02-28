{
  pkgs,
  lib,
  instrument-vmstat,
  benchmarks,
  ...
}:
pkgs.writeShellApplication rec {
  name = "run-benchprog";
  # Note we don't include SSH or Nix in the dependencies here. In Google corp
  # the Nix binaries won't work because of fancy environmental user definition
  # magic.
  runtimeInputs = with pkgs; [
    getopt
    rsync
    falba
    # TODO: this is dumb it shouldn't be a dependency of this binary.
    instrument-vmstat
  ];

  runtimeEnv = {
    BENCHMARK_REGISTRY_JSON =
      let
        # Convert benchmarks to a JSON-friendly subset
        benchmarkPaths = lib.mapAttrs (_: benchmark: {
          native = "${lib.getExe benchmark}";
          in-vm = "${lib.getExe benchmark.in-vm}";
        }) benchmarks;
      in
      pkgs.writers.writeJSON "benchmarks.json" benchmarkPaths;
  };

  text = builtins.readFile ./run-benchprog.sh;

  passthru = {
    benchmarkRegistry = runtimeEnv.BENCHMARK_REGISTRY_JSON;
  };
}
