{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "instrument-vmstat";
  runtimeInputs = with pkgs; [ coreutils gawk ];
  text = builtins.readFile ./vmstat.sh;
}

