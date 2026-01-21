set -eux -o pipefail

# https://github.com/firecracker-microvm/firecracker/blob/main/tests/README.md

cd "$KBN_CACHE_DIR"

# The Firecracker dev tools seem kinda sketchy, unless I run them from a Git
# tree I can't get them to work properly (just copying from the Nix source
# derivation and making it writable didn't work). Haven't looked into this
# carefully.
if [ ! -d firecracker ]; then
    git clone https://github.com/firecracker-microvm/firecracker.git
fi
cd firecracker
git checkout "$FIRECRACKER_REV"

export AWS_EMF_ENVIRONMENT=local
export AWS_EMF_NAMESPACE=local

tools/devtool -y build

# TODO: Hard coding a specific subtest here.
tools/devtool -y test --performance -- \
    -s -m nonci \
    './integration_tests/performance/test_snapshot.py::test_population_latency[vmlinux-5.10.245-PCI_ON-SF_ON-4-6144-None]'