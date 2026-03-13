set -eu -o pipefail

# https://github.com/firecracker-microvm/firecracker/blob/main/tests/README.md

cd "$KBN_CACHE_DIR"

# The Firecracker dev tools seem kinda sketchy, unless I run them from a Git
# tree I can't get them to work properly (just copying from the Nix source
# derivation and making it writable didn't work). Haven't looked into this
# carefully.
if [ ! -d firecracker ]; then
    git clone https://github.com/bjackman/firecracker.git
fi
cd firecracker
git checkout "$FIRECRACKER_REV"

export AWS_EMF_ENVIRONMENT=local
export AWS_EMF_NAMESPACE=local

tools/devtool -y build

# TODO: Hard coding a specific subtest here.
TEST='integration_tests/performance/test_snapshot.py::test_population_latency[vmlinux-5.10.245-PCI_OFF-SF_ON-1-1024-None]'

# You configure the location of the output data by pointing --json-report-file
# to where you want the report.json and it populates the parent directory of
# that file. But also, it does this relative to a subdirectory of the CWD.
# Setting an absolute path doesn't work coz it gets interpreted inside a
# container.
local_out_dir=$(mktemp -d ./tmp.XXXXXXXX)
tools/devtool -y test --performance -- -s -m nonci "$TEST" \
    --json-report-file=../"$local_out_dir"/report.json
# Also this only works with rootful Docker, so these files are owned by root,
# fix that.
sudo chown -R "$USER" "$local_out_dir"
mv "$local_out_dir"/* "$OUT_DIR"
