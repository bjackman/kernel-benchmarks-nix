{
  pkgs,
  lib,
  ...
}:
{
  name,
  rawBenchmark,
  passthru ? { },
}:
pkgs.writeShellScriptBin "${name}-wrapped" ''
  export KBN_CACHE_DIR=''${XDG_CACHE_HOME:-"$HOME"/.cache}/kbn/${name}
  mkdir -p "$KBN_CACHE_DIR"
  exec "${lib.getExe rawBenchmark}" "$@"
''
// passthru
