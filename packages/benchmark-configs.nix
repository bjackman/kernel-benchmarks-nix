{
  pkgs,
  deploy-config,
  falba,
}:
pkgs.writeShellApplication {
  name = "benchmark-configs";
  runtimeInputs = [
    pkgs.docopts
    deploy-config
    falba
  ];
  text = builtins.readFile ../src/deploy-config.sh;
  # Shellcheck can't tell ARGS_* is set.
  excludeShellChecks = [ "SC2154" ];
  extraShellCheckFlags = [
    "--external-sources"
    "--source-path=${pkgs.docopts}/bin"
  ];
}
