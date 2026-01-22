{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "run-benchprog";
  # Note we don't include SSH or Nix in the dependencies here. In Google corp
  # the Nix binaries won't work because of fancy environmental user definition
  # magic.
  runtimeInputs = with pkgs; [ getopt rsync ];
  text = builtins.readFile ./run-benchprog.sh;
}