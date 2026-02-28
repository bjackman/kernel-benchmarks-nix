{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "vmstat";
  runtimeInputs = with pkgs; [
    coreutils
    gawk
  ];
  text = builtins.readFile ./vmstat.sh;
}
