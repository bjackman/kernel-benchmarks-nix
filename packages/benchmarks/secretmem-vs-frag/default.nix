{
  pkgs,
  lib,
  inputs,
  wrapBenchmark,
  ...
}:
let
  name = "secretmem-vs-frag";
  rawBenchmark = pkgs.rustPlatform.buildRustPackage {
    pname = name;
    version = "0.1.0";
    src = ./.;
    cargoHash = "sha256-j3hNaYjILvywWATQtvK1Fj7JDXIWWJ0rIwNRb8yxXIw=";

    meta.mainProgram = name;
  };
in
wrapBenchmark {
  inherit name rawBenchmark;
  worksInNixSandbox = false;
}
