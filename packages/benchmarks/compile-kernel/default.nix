{
  pkgs,
  lib,
  inputs,
  wrapBenchmark,
  ...
}:
let
  name = "compile-kernel";
  kernel = pkgs.linux;
in
wrapBenchmark {
  inherit name;
  rawBenchmark = pkgs.writeShellApplication {
    inherit name;
    runtimeInputs = with pkgs; [
      libelf
      elfutils.dev
      gcc
      bison
      flex
      bc
      rsync
      findutils
      gnumake
      gnused
      gawk
      bash
      gnugrep
      gnutar
      xz
      coreutils
    ];
    runtimeEnv = {
      KBN_KERNEL_SRC = "${kernel.src}";
      KBN_KERNEL_VERSION = "${kernel.version}";
      KBN_ELFUTILS_DEV = "${pkgs.elfutils.dev}";
      KBN_ELFUTILS_OUT = "${pkgs.elfutils.out}";
      KBN_OPENSSL_DEV = "${pkgs.openssl.dev}";
      KBN_OPENSSL_OUT = "${pkgs.openssl.out}";
    };
    text = builtins.readFile ./compile-kernel.sh;
  };
}
