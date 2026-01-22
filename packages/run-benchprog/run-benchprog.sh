#
# Stupid args boilerplate
#

OUT_DIR=

PARSED_ARGUMENTS=$(getopt -o o: --long out-dir: -- "$@")

# shellcheck disable=SC2181
if [ $? -ne 0 ]; then
    echo "Error: Failed to parse arguments." >&2
    usage
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
            usage
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

if [ "$OUT_DIR" == "" ] || [ ! -d "$OUT_DIR" ] || [ ! -z "$(ls -A "$OUT_DIR")" ]; then
    echo "--out-dir must point to an empty directory."
    exit 1
fi

if [ $# -ne 2 ]; then
    echo "Usage: $1 [opts] SSH_TARGET BENCHPROG"
    exit 1
fi
# user@host
SSH_TARGET="$1"
# Nix flake reference
BENCHPROG="$2"

#
# End stupid args boilerplate
#

set -x

id
echo "USER: $USER"
echo "HOME: $HOME"

which nix
export NIX_REMOTE=daemon
nix copy --to ssh-ng://"$SSH_TARGET" "$BENCHPROG"
echo ok

# Figure out the command to run
package_path=$(nix eval --raw "$BENCHPROG")
executable_name=$(nix eval --raw "$BENCHPROG.meta.mainProgram")
executable_path="$package_path/bin/$executable_name"

remote_tmpdir=$(ssh "$SSH_TARGET" mktemp -d)
ssh "$SSH_TARGET" "$executable_path" --out-dir "$remote_tmpdir"
rsync -avz "$SSH_TARGET:$remote_tmpdir" "$OUT_DIR"