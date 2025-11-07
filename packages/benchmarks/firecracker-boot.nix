# Boots up a NixOS VM in Firecracker then shuts down again.
{
  pkgs,
  pkgsUnstable,
  # This is the library function provided by the nixpkgs flake. It needs to be
  # passed in as a package arg. This is probably stupid, there is probably a way
  # to generate the configuration directly from something availble in pkgs.
  nixosSystem,
  # This is the flake input.
  microvm,
  ...
}:
let
  guestConfig = nixosSystem {
    system = "x86_64-linux";
    modules = [
      microvm.nixosModules.microvm
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
            extraConfig.machine-config.secret_free = true;
          };
        };
        # Immediately reboot on startup. In Firecracker, rebooting actually
        # shuts down.
        # Not sure why this doesn't work, mabye it's AI slop:
        # boot.kernelParams = [ "systemd.success_action=reboot" ];
        systemd.services.autoreboot = {
          description = "Immediate reboot after successful boot";
          wantedBy = [ "multi-user.target" ];
          after = [ "multi-user.target" ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "/run/current-system/systemd/bin/systemctl reboot";
          };
        };
        # Console is slow and all the details systemd prints are not interesting.
        # For some reason this doesn't work though.
        # boot.kernelParams = [ "systemd.log_level=err" ];
        # Attempt to avoid unnecesary stuff
        nix.enable = false;
      }

      # This is a bit weird - we're in the definition of the guest, but this is
      # actually also where the VMM for the host gets defined.
      # Use Patrick Roy's modified version of Firecracker that has support for
      # unmapping guest_memfd from the physmap via
      # GUEST_MEMFD_FLAG_NO_DIRECT_MAP.
      {
        nixpkgs.overlays = [
          (final: prev: {
            # Use pkgsUnstable to get new Rust toolchain required by Patrick's code.
            firecracker = pkgsUnstable.callPackage ../firecracker.nix { };
          })
        ];
      }
    ];
  };
  runner = guestConfig.config.microvm.declaredRunner;
in
pkgs.writeShellApplication {
  name = "firecracker-boot";
  runtimeInputs = [ runner ];
  text = ''
    # Seems the API socket is mandatory
    microvm-run --help
  '';
}
# Hang intermediate targets on the output so they can be built for debug inspection.
// {
  inherit guestConfig runner;
}
