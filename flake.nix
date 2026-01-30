{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=25.11";
    firecracker = {
      # HACK: Pin firecracker. Once I've figured out the pacakging for KBN this
      # should be doable in the user instead of in KBN itself.
      url = "github:firecracker-microvm/firecracker?rev=b6c8b2bb57358e9ace56513d1ae3531976f96b3d";
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
        instrument-vmstat = pkgs.callPackage ./packages/instruments/vmstat {};
        run-benchprog = pkgs.callPackage ./packages/run-benchprog { inherit instrument-vmstat; };
      };
      # TODO: Expose generated falba parser configuration.

      benchmarks.${system} =
        # Pretty sure this is dumb and there's a neater way to do this.
        let
          makeBenchprog = package: pkgs.callPackage package { inherit inputs; };
        in
        {
          firecracker-perf-tests = makeBenchprog ./packages/benchmarks/firecracker-perf-tests;
          hello-world = makeBenchprog ./packages/benchmarks/hello-world.nix;
        };

      nixosModules = {
        default = import ./modules/benchprog-support.nix;
        benchmarks.firecracker-perf-tests = import ./packages/benchmarks/firecracker-perf-tests/module.nix;
        # TODO: need a way to report whether a benchprog has an associated module.
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
