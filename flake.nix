{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=25.11";
    firecracker = {
      # Based on upstream branch feature/secret-hiding. Adds a bugfix from me.
      url = "github:bjackman/firecracker?ref=skip-if";
      flake = false;
    };
    falba = {
      url = "github:bjackman/falba";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    microvm = {
      url = "github:microvm-nix/microvm.nix";
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
      lib = pkgs.lib;
      # TODO: does it make sense to use this as a function like this? It means
      # we get to give the helper flake inputs so it can use nixosSystem. The
      # downside is it means things could get confusing if we build benchprogs
      # from a different pkgs than we used for wrapBenchmark? I think this is OK
      # though since it's not "exposed to users" whateve that means here.
      wrapBenchmark = pkgs.callPackage ./lib/wrapBenchmark.nix { inherit self inputs; };
    in
    {
      packages.${system} = rec {
        instrument-vmstat = pkgs.callPackage ./packages/instruments/vmstat { };
        run-benchprog = pkgs.callPackage ./packages/run-benchprog { inherit instrument-vmstat; };
      };
      # TODO: Expose generated falba parser configuration.

      benchmarks.${system} =
        # Pretty sure this is dumb and there's a neater way to do this.
        let
          makeBenchprog =
            package:
            pkgs.callPackage package {
              inherit inputs wrapBenchmark;
              inherit (nixpkgs.lib) nixosSystem;
            };
        in
        {
          firecracker-perf-tests = makeBenchprog ./packages/benchmarks/firecracker-perf-tests;
          hello-world = makeBenchprog ./packages/benchmarks/hello-world.nix;
          stress-ng = makeBenchprog ./packages/benchmarks/stress-ng;
        };

      nixosModules = {
        default = import ./modules/benchprog-support.nix;
        benchmarks.firecracker-perf-tests = import ./packages/benchmarks/firecracker-perf-tests/module.nix;
        # TODO: need a way to report whether a benchprog has an associated module.
      };

      formatter.${system} = pkgs.nixfmt-tree;

      # TODO: Add checks for the rest of the benchmarks. For ones that don't
      # couple to the OS, run them natively.
      checks.${system}.bench-hello-world = pkgs.runCommand "check-bench-hello-world" { } ''
        # Disable vsock since that doesn't work in the Nix sandbox.
        timeout 30 ${lib.getExe self.benchmarks.${system}.hello-world.in-vm} --vsock-cid=-1
        touch $out
      '';

      # This devShell provides a bunch of tools for running these benchmarks.
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixos-rebuild
          falba
        ];
      };
    };
}
