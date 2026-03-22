{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "nixos";
  text = builtins.readFile ./instrument-nixos.sh;
}
