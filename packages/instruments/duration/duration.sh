#!/bin/bash
set -euo pipefail

BEFORE_FILE="$KBN_INSTRUMENT_DIR/before"
AFTER_FILE="$KBN_INSTRUMENT_DIR/after"
DURATION_FILE="$KBN_INSTRUMENT_DIR/duration.txt"

usage() {
    echo "Usage: $0 [--before | --after]"
    exit 1
}

if [[ $# -eq 0 ]]; then
    usage
fi

case "$1" in
    --before)
        date +%s%N > "$BEFORE_FILE"
        ;;
    --after)
        date +%s%N > "$AFTER_FILE"

        if [[ ! -f "$BEFORE_FILE" ]]; then
            echo "Error: --before snapshot not found at $BEFORE_FILE" >&2
            exit 1
        fi

        start=$(cat "$BEFORE_FILE")
        end=$(cat "$AFTER_FILE")

        duration_ns=$((end - start))
        duration_us=$((duration_ns / 1000))
        echo "$duration_us" > "$DURATION_FILE"
        ;;
    *)
        usage
        ;;
esac
