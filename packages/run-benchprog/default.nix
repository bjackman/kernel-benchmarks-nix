{
  pkgs,
  lib,
  instruments,
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
      pkgs.writers.writeJSON "instruments.json" benchmarkPaths;
    INSTRUMENT_REGISTRY_JSON =
      let
        instrumentPaths = lib.mapAttrs (_: instrument: lib.getExe instrument) instruments;
      in
      pkgs.writers.writeJSON "instruments.json" instrumentPaths;
  };

  text = builtins.readFile ./run-benchprog.sh;

  passthru = {
    benchmarkRegistry = runtimeEnv.BENCHMARK_REGISTRY_JSON;
    instrumentRegistry = runtimeEnv.INSTRUMENT_REGISTRY_JSON;
  };
}
