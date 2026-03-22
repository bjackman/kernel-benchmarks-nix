{
  pkgs,
  lib,
  vmstat,
}:

pkgs.runCommand "instrument-vmstat-test"
  {
    nativeBuildInputs = [
      vmstat
      pkgs.falba
      pkgs.jq
      pkgs.duckdb
    ];
  }
  ''
    export KBN_INSTRUMENT_DIR=$(pwd)/artifacts/instrumentation/vmstat
    mkdir -p "$KBN_INSTRUMENT_DIR"
    vmstat --before
    vmstat --after

    mkdir falba-db
    cp ${vmstat.falba-parsers-json} falba-db/parsers.json

    falba import --test-name vmstat-test --result-db ./falba-db artifacts/instrumentation

    falba sql --result-db ./falba-db "SELECT metric, int_value FROM metrics ORDER BY metric" > metrics.txt

    # Silly sanity check.
    grep "vmstat_diff_pgfault" metrics.txt
    grep "vmstat_diff_nr_free_pages" metrics.txt

    touch $out
  ''
