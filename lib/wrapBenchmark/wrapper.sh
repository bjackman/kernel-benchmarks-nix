# Expects:
# - KBN_BENCH_NAME
# - KBN_RAW_BENCH_EXE

OUT_DIR=

PARSED_ARGUMENTS=$(getopt -o o: --long out-dir: -- "$@")

# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    echo "Error: Failed to parse arguments." >&2
    exit 1
fi
eval set -- "$PARSED_ARGUMENTS"
while true; do
    case "$1" in
        -o|--out-dir)
            OUT_DIR="$2"
            shift 2
            ;;
        -h|--help)
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Unexpected argument, script bug? $1" >&2
            exit 1
            ;;
    esac
done

if [ "$OUT_DIR" == "" ]; then
    OUT_DIR="$(mktemp -d)"
    echo "WARNING: --out-dir not set, using $OUT_DIR"
fi

if [ ! -d "$OUT_DIR" ] || [ ! -z "$(ls -A "$OUT_DIR")" ]; then
    echo "--out-dir must point to an empty directory."
    exit 1
fi

export OUT_DIR

BASE_CACHE="${CACHE_DIRECTORY:-${XDG_CACHE_HOME:-${HOME:+$HOME/.cache}}}"
export KBN_CACHE_DIR="$BASE_CACHE/kbn/$KBN_BENCH_NAME"
mkdir -p "$KBN_CACHE_DIR"
exec "$KBN_RAW_BENCH_EXE" "$@"
