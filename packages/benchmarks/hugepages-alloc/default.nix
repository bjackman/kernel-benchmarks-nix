# This benchmark just does a single allocation of a bunch of hugepages by
# writing nr_hugepages in sysfs.
{
  pkgs,
  lib,
  inputs,
  wrapBenchmark,
  ...
}:
let
  name = "hugepages-alloc";
  rawBenchmark = pkgs.writeShellApplication {
    inherit name;
    text = ''
            NR_HUGEPAGES=24552

            while [ $# -gt 0 ]; do
                case "$1" in
                    -n|--nr-hugepages)
                        NR_HUGEPAGES="$2"
                        shift 2
                        ;;
                    *)
                        shift
                        ;;
                esac
            done

            HUGEPAGES_FILE="/sys/kernel/mm/hugepages/hugepages-2048kB/nr_hugepages"

            if [ ! -f "$HUGEPAGES_FILE" ]; then
                echo "Error: Hugepages file not found at $HUGEPAGES_FILE" >&2
                exit 1
            fi

            echo "Attempting to allocate $NR_HUGEPAGES hugepages..."
            # shellcheck disable=SC2024
            if ! echo "$NR_HUGEPAGES" > "$HUGEPAGES_FILE"; then
                echo "Error: Failed to write to $HUGEPAGES_FILE." >&2
                exit 1
            fi

            ALLOCATED=$(cat "$HUGEPAGES_FILE")
            echo "Allocated hugepages: $ALLOCATED"

            if [ -z "''${OUT_DIR:-}" ]; then
                echo "Error: OUT_DIR is not set" >&2
                exit 1
            fi

            mkdir -p "$OUT_DIR"
            cat <<EOF > "$OUT_DIR/hugepages_alloc_summary.json"
      {
        "requested_hugepages": $NR_HUGEPAGES,
        "allocated_hugepages": $ALLOCATED
      }
      EOF
            echo "Summary written to $OUT_DIR/hugepages_alloc_summary.json"
    '';
  };
in
wrapBenchmark {
  inherit name rawBenchmark;
  requiresRoot = true;
  nixosModules = [
    ({
      virtualisation.vmVariant.virtualisation.memorySize = 32 * 1024; # MiB
    })
  ];
  passthru = rec {
    falba-parsers = import ./falba-parsers.nix;
    falba-parsers-json = pkgs.writers.writeJSON "falba-parsers.json" falba-parsers;
  };
}
