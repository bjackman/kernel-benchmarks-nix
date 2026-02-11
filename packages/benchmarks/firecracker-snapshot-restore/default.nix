# Boots up a NixOS VM in Firecracker then shuts down again.
# This uses microvm.nix out of laziness but doesn't take very much advantage of
# it, probably it should just be calling Firecracker directly.
{
  pkgs,
  # This is the library function provided by the nixpkgs flake. It needs to be
  # passed in as a package arg. This is probably stupid, there is probably a way
  # to generate the configuration directly from something availble in pkgs.
  nixosSystem,
  inputs,
  ...
}:
let
  firecracker = pkgs.callPackage ../../firecracker.nix {
    src = inputs.firecracker;
  };
  baseModules = [
    inputs.microvm.nixosModules.microvm
    {
      microvm = {
        hypervisor = "firecracker";
        firecracker. extraArgs = [ "--no-seccomp" ];
      };
      # This is a bit weird (we are in a module that defines the guest but
      # actually this configures the host) - it ensures that the microvm runner
      # users the provided firecracker binary.
      nixpkgs.overlays = [ (final: prev: { inherit firecracker; }) ];
    }
  ];
  config = nixosSystem {
    system = "x86_64-linux";
    modules = baseModules;
  };
  microvmRunner = config.config.microvm.declaredRunner;
  # Not actually a script just a "library" to be sourced.
  shLib = pkgs.writeShellScriptBin "lib.sh" (builtins.readFile ./lib.sh);
  # This script generates a snapshot file (mem) and vmstate file in the CWD.
  gen-snapshot = pkgs.writeShellApplication {
    name = "firecracker-gen-snapshot";
    runtimeInputs = [ pkgs.curl microvmRunner shLib ];
    extraShellCheckFlags = [
      "--external-sources"
      "--source-path=${shLib}/bin"
    ];
    text = builtins.readFile ./gen-snapshot.sh;
  };
in
pkgs.writeShellApplication {
  name = "firecracker-snapshot-restore";
  runtimeInputs = [ pkgs.curl firecracker shLib gen-snapshot ];
  text = builtins.readFile ./snapshot-restore.sh;
  extraShellCheckFlags = [
    "--external-sources"
    "--source-path=${shLib}/bin"
  ];
  passthru = { inherit gen-snapshot shLib; };
}