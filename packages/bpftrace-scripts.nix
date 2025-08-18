{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "bpftrace-scripts";
  version = "0.1";
  src = pkgs.writeScriptBin "asi_exits.bpftrace" (builtins.readFile ../src/asi_exits.bpftrace);
  installPhase = ''
    mkdir -p $out/bin
    makeWrapper $src/bin/asi_exits.bpftrace $out/bin/bpftrace_asi_exits \
      --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.bpftrace ]}
  '';
  buildInputs = [ pkgs.makeWrapper ];
}
