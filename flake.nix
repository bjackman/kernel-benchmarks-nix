{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=25.11";
    firecracker = {
      url = "github:firecracker-microvm/firecracker?ref=feature/secret-hiding";
      flake = false;
    };
    falba = {
      url = "github:bjackman/falba";
      inputs.nixpkgs.follows = "nixpkgs";
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
      pkgs = import nixpkgs {
        inherit system;
        overlays = [
          (final: prev: {
            falba = inputs.falba.packages.${system}.default;
          })
        ];
      };
    in
    {
      packages.${system} = rec {
        run-benchprog = pkgs.callPackage ./packages/run-benchprog { };
      };

      benchmarks.${system}.firecracker-perf-tests =
        pkgs.callPackage ./packages/benchmarks/firecracker-perf-tests
          {
            inherit inputs;
          };

      nixosModules = {
        default = import ./modules/benchprog-support.nix;
        benchmarks.firecracker-perf-tests = import ./packages/benchmarks/firecracker-perf-tests/module.nix;
      };

      formatter.${system} = pkgs.nixfmt-tree;

      # This devShell provides a bunch of tools for running these benchmarks.
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixos-rebuild
          falba
        ];
      };
    };
}
