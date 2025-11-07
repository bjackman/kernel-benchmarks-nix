# Boots up a NixOS VM in Firecracker then shuts down again.
{
  pkgs,
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
      {
        networking.hostName = "my-microvm";
        users.users.root.password = "";
        microvm.hypervisor = "firecracker";
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
