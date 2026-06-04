# Expects:
# - KBN_KERNEL_SRC
# - KBN_KERNEL_VERSION
# - KBN_ELFUTILS_DEV
# - KBN_ELFUTILS_OUT
# - KBN_OPENSSL_DEV
# - KBN_OPENSSL_OUT
# - OUT_DIR (from wrapBenchmark)

export HOSTCFLAGS="-isystem $KBN_ELFUTILS_DEV/include"
export HOSTLDFLAGS="-L $KBN_ELFUTILS_OUT/lib"
export HOSTCFLAGS="$HOSTCFLAGS -isystem $KBN_OPENSSL_DEV/include"
export HOSTLDFLAGS="$HOSTLDFLAGS -L $KBN_OPENSSL_OUT/lib"

output="$(mktemp -d)"
# shellcheck disable=SC2064
trap "rm -rf $output" EXIT

echo "Unpacking kernel source $KBN_KERNEL_SRC in $output"
cd "$output"
tar xJf "$KBN_KERNEL_SRC"
cd "linux-$KBN_KERNEL_VERSION"

echo "Running tinyconfig"
make -sj tinyconfig

echo "Building vmlinux"
start_time=$(date +%s)
make -sj"$(nproc)" vmlinux
end_time=$(date +%s)

duration=$((end_time - start_time))
echo "Build finished in $duration seconds"

cat <<EOF > "$OUT_DIR/metrics.yaml"
build_duration_seconds: $duration
EOF
