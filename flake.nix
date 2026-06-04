{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=26.05";
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
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      treefmt-nix,
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
      treefmtConfig = treefmt-nix.lib.evalModule pkgs {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
        programs.rustfmt.enable = true;
        programs.prettier = {
          enable = true;
          includes = [ "*.md" ];
        };
        settings.formatter.prettier = {
          options = [
            "--print-width"
            "80"
            "--prose-wrap"
            "always"
          ];
        };
      };
      # TODO: does it make sense to use this as a function like this? It means
      # we get to give the helper flake inputs so it can use nixosSystem. The
      # downside is it means things could get confusing if we build benchprogs
      # from a different pkgs than we used for wrapBenchmark? I think this is OK
      # though since it's not "exposed to users" whateve that means here.
      wrapBenchmark = pkgs.callPackage ./lib/wrapBenchmark { inherit self inputs; };
    in
    {
      packages.${system} = rec {
        run-benchprog = pkgs.callPackage ./packages/run-benchprog {
          benchmarks = self.benchmarks.${system};
          instruments = self.instruments.${system};
        };

        run-benchprog-integration-test = pkgs.callPackage ./packages/run-benchprog/integration-test.nix {
          inherit (self.packages.${system}) run-benchprog;
          hello-world-in-vm = self.benchmarks.${system}.hello-world.in-vm;
        };

        falba-parsers =
          let
            # Collect all benchmarks and instruments that have a falba-parsers-json passthru.
            allProviders = lib.filterAttrs (_: p: p ? falba-parsers-json) (
              self.benchmarks.${system} // self.instruments.${system}
            );
            # Map them to their parser JSON files, naming each file <name>.json.
            parserFiles = lib.mapAttrsToList (
              name: provider:
              pkgs.runCommand "${name}-falba-parsers.json" { } ''
                mkdir -p $out
                cp ${provider.falba-parsers-json} $out/${name}.json
              ''
            ) allProviders;
          in
          pkgs.symlinkJoin {
            name = "falba-parsers";
            paths = parserFiles;
          };

        impure-tests =
          let
            impureBenchmarks = lib.filterAttrs (_: b: b.impureTest != null) self.benchmarks.${system};
            tests = lib.mapAttrsToList (name: bench: bench.impureTest) impureBenchmarks;
            runAll = pkgs.writeShellScriptBin "impure-tests" ''
              for t in ${builtins.concatStringsSep " " (map (t: lib.getExe t) tests)}; do
                "$t"
              done
              "${lib.getExe self.packages.${system}.run-benchprog-integration-test}"
            '';
          in
          runAll // lib.mapAttrs (name: bench: bench.impureTest) impureBenchmarks;
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
          secretmem-vs-frag = makeBenchprog ./packages/benchmarks/secretmem-vs-frag;
          stress-ng = makeBenchprog ./packages/benchmarks/stress-ng;
        };

      instruments.${system} = {
        vmstat = pkgs.callPackage ./packages/instruments/vmstat { };
        nixos = pkgs.callPackage ./packages/instruments/nixos { };
        uname = pkgs.callPackage ./packages/instruments/uname.nix { };
      };

      nixosModules = {
        default = import ./modules/benchprog-support.nix;
        benchmarks.firecracker-perf-tests = import ./packages/benchmarks/firecracker-perf-tests/module.nix;
        # TODO: need a way to report whether a benchprog has an associated module.
      };

      formatter.${system} = treefmtConfig.config.build.wrapper;

      checks.${system} =
        let
          testable = self.benchmarks.${system} // self.instruments.${system};
        in
        lib.mapAttrs (name: drv: drv.heavyCheck) (
          lib.filterAttrs (_: b: b ? heavyCheck && b.heavyCheck != null) testable
        )
        // {
          formatting = treefmtConfig.config.build.check self;
        };

      # This devShell provides a bunch of tools for running these benchmarks.
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [
          nixos-rebuild
          falba
          cargo
          rustc
        ];
        FALBA_PARSERS_PATH = self.packages.${system}.falba-parsers;
      };
    };
}
