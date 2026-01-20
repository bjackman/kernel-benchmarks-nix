{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=25.11";
  };

  outputs =
    {
      self,
      nixpkgs,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages."${system}" = rec {
        benchmarks.firecracker-perf-tests =
          pkgs.callPackage ./packages/benchmarks/firecracker-perf-tests
            { };
      };

      formatter."${system}" = pkgs.nixfmt-tree;

      # This devShell provides a bunch of tools for running these benchmarks.
      devShells."${system}".default = pkgs.mkShell {
        packages = [
          pkgs.nixos-rebuild
        ];
      };
    };
}
