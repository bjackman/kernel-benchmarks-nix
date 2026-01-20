{
  pkgs,
  name,
  rawBenchmark,
  lib,
  ...
}:
pkgs.writeShellScriptBin "${name}-wrapped" ''
  export KBN_CACHE_DIR=''${XDG_CACHE_HOME:-"$HOME"/.cache}/${name}
  mkdir -p "$KBN_CACHE_DIR"
  exec "${lib.getExe rawBenchmark}" "$@"
''
