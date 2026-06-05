# This benchmark just does a single allocation of a bunch of hugepages by
# writing nr_hugepages in sysfs.
# --size sets the overall size of the hugepages to allocate (rounded up to size
# of hugepage). --nr-hugepages instead sets the count of pages to allocate.
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
            parse_size_to_hugepages() {
                local size_str="$1"
                # Remove trailing whitespace
                size_str=$(echo "$size_str" | tr -d '[:space:]')

                # Extract number and suffix
                if [[ "$size_str" =~ ^([0-9]+)([kKmMgGtT]?[bB]?)$ ]]; then
                    local num="''${BASH_REMATCH[1]}"
                    local suffix="''${BASH_REMATCH[2]}"
                else
                    echo "Error: Invalid size format: $size_str" >&2
                    exit 1
                fi

                local multiplier=1
                case "$suffix" in
                    [kK]|[kK][bB])
                        multiplier=1024
                        ;;
                    [mM]|[mM][bB])
                        multiplier=$((1024 * 1024))
                        ;;
                    [gG]|[gG][bB])
                        multiplier=$((1024 * 1024 * 1024))
                        ;;
                    [tT]|[tT][bB])
                        multiplier=$((1024 * 1024 * 1024 * 1024))
                        ;;
                    "")
                        multiplier=1
                        ;;
                    *)
                        echo "Error: Unsupported suffix: $suffix" >&2
                        exit 1
                        ;;
                esac

                local total_bytes
                total_bytes=$((num * multiplier))

                local hp_size=$((2 * 1024 * 1024)) # 2MB

                local nr_hugepages=$(( (total_bytes + hp_size - 1) / hp_size ))

                echo "$nr_hugepages"
            }

            SIZE=""
            NR_HUGEPAGES=""

            while [ $# -gt 0 ]; do
                case "$1" in
                    -s|--size)
                        SIZE="$2"
                        shift 2
                        ;;
                    -n|--nr-hugepages)
                        NR_HUGEPAGES="$2"
                        shift 2
                        ;;
                    *)
                        shift
                        ;;
                esac
            done

            if [ -n "$SIZE" ] && [ -n "$NR_HUGEPAGES" ]; then
                echo "--size and --nr-hugepages are mutually exclusive"
                exit 1
            fi

            if [ -z "$SIZE" ] && [ -z "$NR_HUGEPAGES" ]; then
                NR_HUGEPAGES=24552
            fi

            if [ -n "$SIZE" ]; then
                NR_HUGEPAGES=$(parse_size_to_hugepages "$SIZE")
            fi

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
