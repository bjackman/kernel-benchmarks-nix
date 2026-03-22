{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "instrument-nixos";
  text = builtins.readFile ./instrument-nixos.sh;
}
