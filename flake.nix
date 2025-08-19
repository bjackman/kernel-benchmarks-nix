{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=25.05";
    falba = {
      url = "github:bjackman/falba-go";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      falba,
    }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # https://github.com/NixOS/nixpkgs/pull/408168/
        overlays = [
          (final: prev: {
            docopts = prev.docopts.overrideAttrs (prev: {
              postInstall = ''
                cp ${prev.src}/docopts.sh $out/bin/docopts.sh
                chmod +x $out/bin/docopts.sh
              '';
            });
          })
        ];
      };
    in
    {
      packages."${system}" = rec {
        # This is the main entry point for running benchmarks. You run it on
        # your local development machine and it deploys configs, runs benchmarks
        # on them, and fetches result data.
        benchmark-configs = pkgs.callPackage ./packages/benchmark-configs.nix {
          inherit deploy-config;
          falba = falba.packages.x86_64-linux.falba;
        };

        # Default script for deploying a NixOS configuration to a host.
        deploy-config = pkgs.callPackage ./packages/deploy-config.nix { };

        # Outer wrapper for run-benchmark. Optionally boots a VM and runs it
        # inside that.
        benchmarks-wrapper = pkgs.callPackage ./packages/benchmarks-wrapper.nix {
          # Here we pass packages' dependencies as arguments. I'm not sure if
          # this is good Nix practice or if it's preferred to add them to pkgs
          # via an overlay or something.
          inherit bpftrace-scripts;
          inherit run-benchmark;
        };

        bpftrace-scripts = pkgs.callPackage ./packages/bpftrace-scripts.nix { };

        # Very thin inner wrapper, mostly just a helper for benchmarks-wrapper.
        # This runs inside the guest when running on a VM.
        run-benchmark = pkgs.callPackage ./packages/run-benchmark.nix {
          inherit compile-kernel;
        };

        # Package that compiles a kernel, as a "benchmark"
        compile-kernel = pkgs.callPackage ./packages/benchmarks/compile-kernel.nix { };
      };

      formatter."${system}" = pkgs.nixfmt-tree;
      devShells."${system}".default = pkgs.mkShell {
        packages = [ pkgs.nixos-rebuild ];
      };
    };
}
