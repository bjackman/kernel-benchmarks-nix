{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=25.05";
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
      packages."${system}" = {
        # Package that compiles a kernel, as a "benchmark"
        compile-kernel = pkgs.callPackage ./packages/benchmarks/compile-kernel.nix { };
      };

      formatter."${system}" = pkgs.nixfmt-tree;
      devShells."${system}".default = pkgs.mkShell {
        packages = [ pkgs.nixos-rebuild ];
      };
    };
}
