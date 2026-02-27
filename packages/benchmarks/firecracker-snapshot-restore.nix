# Boots up a NixOS VM in Firecracker then shuts down again.
{
  pkgs,
  # This is the library function provided by the nixpkgs flake. It needs to be
  # passed in as a package arg. This is probably stupid, there is probably a way
  # to generate the configuration directly from something availble in pkgs.
  nixosSystem,
  firecracker,
  ...
}:
let
  baseModules = [
    inputs.microvm.nixosModules.microvm
    "${pkgs.path}/nixos/modules/profiles/minimal.nix"
    {
      networking.hostName = "my-microvm";
      users.users.root.password = "";
      microvm = {
        hypervisor = "firecracker";
        firecracker = {
          # Set GUEST_MEMFD_FLAG_NO_DIRECT_MAP. This requires synchronous
          # storage IO (dunno why).
          driveIoEngine = "Sync";
          # Support booting on super minimal kernel configs
          extraArgs = [ "--no-seccomp" ];
        };
      };
      # Console is slow and all the details systemd prints are not interesting.
      # For some reason this doesn't work though.
      # boot.kernelParams = [ "systemd.log_level=err" ];
      # Attempt to avoid unnecesary stuff
      nix.enable = false;
    }

    # This ensures that the microvm is run via the provided firecracker binary.
    {
      nixpkgs.overlays = [ (final: prev: { inherit firecrasker; }) ];
    }
  ];
  config = nixosSystem {
    system = "x86_64-linux";
    modules = baseModules;
  };
  microvmRunner = config.config.microvm.declaredRunner;
in
pkgs.writeShellApplication {
  name = "firecracker-snapshot-restore";
  version = "0.1";
  text = '''';
}
