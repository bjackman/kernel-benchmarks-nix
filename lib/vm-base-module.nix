{
  pkgs,
  config,
  lib,
  ...
}:
let
  # I/O port that will be used for the isa-debug-exit device. I don't know
  # how arbitrary this value is, I got it from Gemini who I suspect is
  # cargo-culting from https://os.phil-opp.com/testing/
  qemuExitPortHex = "0xf4";
in
{
  boot = {
    consoleLogLevel = 0;
    initrd.verbose = false;
    kernelParams = [
      "quiet"
      "udev.log_level=3"
      "rd.systemd.show_status=false"
      "rd.udev.log_level=3"
      "udev.log_priority=3"
    ];
  };

  virtualisation.vmVariant.virtualisation = {
    graphics = false;
    qemu.options = [
      # This BIOS doesn't mess up the terminal and is apparently faster.
      "-bios"
      "qboot.rom"
      "-device"
      "isa-debug-exit,iobase=${qemuExitPortHex},iosize=0x04"
    ];
    # Tell the VM runner script that it should mount a directory on the
    # host, named in the environment variable, to /mnt/kbn-output. That
    # variable must point to a directory. This is coupled with the script
    # content below.
    sharedDirectories = {
      kbn-output = {
        source = "$KBN_OUTPUT_HOST";
        target = "/mnt/kbn-output";
      };
    };
    # Attempt to ensure there's space left over in the rootfs (which
    # may be where /tmp is).
    diskSize = lib.mkDefault (2 * 1024); # Megabytes
    # This seems to speed up boot a bit.
    cores = 8;
    memorySize = lib.mkDefault (6 * 1024); # Megabytes
  };

  boot.tmp.useTmpfs = true;

  # This service does the forwarding of the benchmark exit code to
  # the QEMU hypervisor. I think the proper way to do this would be
  # /usr/lib/systemd/systemd-shutdown/ but I couldn't get that
  # working so whatever.
  systemd.services.kbn-shutdown-exit = {
    unitConfig.DefaultDependencies = false;
    script = ''
      set +x
      if [ -f /run/kbn-exit-code ]; then
        CODE=$(cat /run/kbn-exit-code)
      else
        echo "/run/kbn-exit-code missing"
        CODE=213
      fi
      if [ "$CODE" -ne 0 ]; then
        # Writing the value v to the isa-debug-exit port will cause QEMU to
        # immediately exit with the exit code `v << 1 | 1`.
        ${pkgs.ioport}/bin/outb -- ${qemuExitPortHex} $(( CODE - 1 ))
      fi
    '';
    serviceConfig = {
      Type = "oneshot";
      StandardOutput = "tty";
      StandardError = "tty";
    };
    after = [ "shutdown.target" ];
    before = [ "poweroff.target" ];
    wantedBy = [ "poweroff.target" ];
  };

  # Don't bother storing logs to disk, that seems like it will just
  # occasionally lead to unnecessary slowdowns for log rotation and
  # stuff.
  services.journald.storage = "volatile";

  services.getty.autologinUser = "root";
  services.openssh = {
    enable = true;
    settings = {
      PermitEmptyPasswords = "yes";
      PermitRootLogin = "yes";
    };
  };
  users.users.root.initialHashedPassword = "";
  security.pam.services.sshd.allowNullPassword = true;

  system.stateVersion = "25.11";
}
