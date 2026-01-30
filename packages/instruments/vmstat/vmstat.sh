#!/bin/bash

set -euo pipefail

VMSTAT_DIR="${KBN_INSTRUMENT_DIR}/vmstat"
mkdir -p "$VMSTAT_DIR"

BEFORE_FILE="$VMSTAT_DIR/before"
AFTER_FILE="$VMSTAT_DIR/after"
DIFF_FILE="$VMSTAT_DIR/diff"

usage() {
    echo "Usage: $0 [--before | --after]"
    exit 1
}

if [[ $# -eq 0 ]]; then
    usage
fi

case "$1" in
    --before)
        cp /proc/vmstat "$BEFORE_FILE"
        ;;
    --after)
        cp /proc/vmstat "$AFTER_FILE"

        # TODO: This is dumb, this should be done in falba not on the target.
        # Calculate diff if before file exists
        if [[ ! -f "$BEFORE_FILE" ]]; then
            echo "Error: --before snapshot not found at $BEFORE_FILE" >&2
            exit 1
        fi
        awk '
            # Load the "before" file into an associative array
            NR == FNR {
                before[$1] = $2
                next
            }
            # Process the "after" file
            {
                key = $1
                after_val = $2
                if (key in before) {
                    diff = after_val - before[key]
                    printf "%s %d\n", key, diff
                }
            }
        ' "$BEFORE_FILE" "$AFTER_FILE" > "$DIFF_FILE"
        ;;
    *)
        usage
        ;;
esac