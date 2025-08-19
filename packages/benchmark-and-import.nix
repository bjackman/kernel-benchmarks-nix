{
  pkgs,
  falba,
}:
pkgs.writeShellApplication {
  name = "benchmark-and-import";
  runtimeInputs =
    [
      falba
    ]
    ++ (with pkgs; [
      docopts
      gawk # Required by docopts
    ]);
  text = builtins.readFile ../src/benchmark-and-import.sh;
  excludeShellChecks = [ "SC2154" ]; # Shellcheck can't tell ARGS_* is set.
  extraShellCheckFlags = [
    "--external-sources"
    "--source-path=${pkgs.docopts}/bin"
  ];
}
