{ pkgs, ... }:
let
  kernel = pkgs.linux;
in
pkgs.writeShellApplication {
  name = "bench-compile-kernel";
  runtimeInputs = with pkgs; [
    libelf
    elfutils.dev
    gcc
    bison
    flex
    bc
    rsync

    # We sometimes run this in an extremely minimal environment via
    # systemd so we ned to be pretty verbose about specifying stuff
    # that's otherwise pretty basic.
    findutils
    gnumake
    gnused
    gawk
    bash
    gnugrep
    gnutar
    xz
  ];
  text = ''
    # Nix does this for you in the build environment but doesn't
    # really make libraries available to the toolchain at runtime.
    # Normally I think people would just use a nix-shell or something
    # that provides the relevant wrappers? I'm not sure, I might be
    # barking up the wrong tree.
    # Anyway, here's a super simple way to make the necessary
    # libraries available:
    export HOSTCFLAGS="-isystem ${pkgs.elfutils.dev}/include"
    export HOSTLDFLAGS="-L ${pkgs.elfutils.out}/lib"
    export HOSTCFLAGS="$HOSTCFLAGS -isystem ${pkgs.openssl.dev}/include"
    export HOSTLDFLAGS="$HOSTLDFLAGS -L ${pkgs.openssl.out}/lib"

    output="$(mktemp -d)"
    trap 'rm -rf $output' EXIT
    echo "Unpacking kernel source ${kernel.src} in $output"
    cd "$output"
    tar xJf ${kernel.src}
    cd "linux-${kernel.version}"

    make -sj tinyconfig
    make -sj"$(nproc)" vmlinux
  '';
}
