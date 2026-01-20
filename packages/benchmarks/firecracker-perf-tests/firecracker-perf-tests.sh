set -eux -o pipefail

# https://github.com/firecracker-microvm/firecracker/blob/main/tests/README.md

# Probably it's possible to run this from an arbitrary location but simple easy
# approach is just to have a local writable tree so we can blindly follow docs.
cd "$KBN_CACHE_DIR"
cp -R --no-preserve=ownership "$FIRECRACKER_SRC"/* .

# Need to be able to modify the tree so chmod, but the firecracker devtools is a
# Docker mess that can leave behind root-owned files. Just ignore those.
find .  -user $(whoami) | xargs chmod u+w

export AWS_EMF_ENVIRONMENT=local
export AWS_EMF_NAMESPACE=local

tools/devtool -y build

# TODO: Hard coding a specific subtest here.
tools/devtool -y test --performance -- \
    -s -m nonci \
    './integration_tests/performance/test_snapshot.py::test_population_latency[vmlinux-5.10.245-PCI_ON-SF_ON-4-6144-None]'