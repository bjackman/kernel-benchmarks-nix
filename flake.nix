{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=25.11";
    firecracker = {
      url = "github:firecracker-microvm/firecracker?ref=feature/secret-hiding";
      flake = false;
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      ...
    }@inputs:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };
    in
    {
      packages."${system}" = rec {
        benchmarks.firecracker-perf-tests = pkgs.callPackage ./packages/benchmarks/firecracker-perf-tests {
          inherit inputs;
        };
      };

      nixosModules.benchmarks.firecracker-perf-tests = import ./packages/benchmarks/firecracker-perf-tests/module.nix;

      formatter."${system}" = pkgs.nixfmt-tree;

      # This devShell provides a bunch of tools for running these benchmarks.
      devShells."${system}".default = pkgs.mkShell {
        packages = [
          pkgs.nixos-rebuild
        ];
      };
    };
}
