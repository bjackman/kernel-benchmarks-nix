{
  pkgs,
  lib,
  secretmem-stressor,
}:
pkgs.runCommand "stressor-secretmem-test"
  {
    nativeBuildInputs = [
      secretmem-stressor
      pkgs.falba
      pkgs.jq
      pkgs.duckdb
    ];
  }
  ''
    export KBN_STRESSOR_DIR=$(pwd)/artifacts/stressors/secretmem
    mkdir -p "$KBN_STRESSOR_DIR"

    # Start the stressor.
    # It might fail if the host kernel doesn't support secretmem, but
    # stress-ng should still run or at least we write the status.json.
    # Wait, if stress-ng fails immediately, does --start fail?
    # --start runs nohup stress-ng ... & and exits 0.
    # So --start should succeed even if stress-ng dies immediately.
    stress-secretmem --start
    sleep 1
    stress-secretmem --stop

    mkdir falba-db
    cp ${secretmem-stressor.falba-parsers-json} falba-db/parsers.json

    # falba import expects the root directory containing artifacts.
    # We have artifacts/stressors/secretmem/status.json.
    # So we pass 'artifacts'.
    falba import --test-name secretmem-test --result-db ./falba-db artifacts

    # Verify that the fact is present and true in the 'results' table.
    falba sql --result-db ./falba-db "SELECT stressed_secretmem FROM results" > result.txt
    cat result.txt
    grep -E "true|1|t" result.txt

    touch $out
  ''
