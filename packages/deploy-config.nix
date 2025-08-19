{ pkgs }:
pkgs.writeShellApplication {
  name = "deploy-config";
  runtimeInputs = [
    pkgs.docopts
    pkgs.nixos-rebuild
  ];
  text = builtins.readFile ../src/deploy-config.sh;
  # Shellcheck can't tell ARGS_* is set.
  excludeShellChecks = [ "SC2154" ];
  extraShellCheckFlags = [
    "--external-sources"
    "--source-path=${pkgs.docopts}/bin"
  ];
}
