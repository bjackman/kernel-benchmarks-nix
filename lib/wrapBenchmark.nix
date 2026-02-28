{
  pkgs,
  lib,
  inputs,
  self,
  ...
}:
# This function takes a base benchprog (TODO: document exactly what that means)
# and turns it into a fully fledged benchprog package.
{
  name,
  rawBenchmark,
  passthru ? { },
  # Modules that are required for the host the benchprog is running in.
  nixosModules ? [ ],
  requiresInternet ? false,
}:
let
  wrappedProg = pkgs.writeShellScriptBin "${name}" ''
    export KBN_CACHE_DIR=''${XDG_CACHE_HOME:-"$HOME"/.cache}/kbn/${name}
    mkdir -p "$KBN_CACHE_DIR"
    exec "${lib.getExe rawBenchmark}" "$@"
  '';
in
wrappedProg
// {
  # This produces a version of the benchmark that gets run in a NixOS VM. The
  # purposes of this are a) for benchmarking a host's performance as a
  # hypervisor and b) for integration-testing the benchmark script.
  in-vm =
    let
      hostName = "testvm-${name}";
      nixosConfig = inputs.nixpkgs.lib.nixosSystem {
        system = pkgs.stdenv.hostPlatform.system;
        specialArgs = { inherit self; };
        modules =
          let
            # I/O port that will be used for the isa-debug-exit device. I don't know
            # how arbitrary this value is, I got it from Gemini who I suspect is
            # cargo-culting from https://os.phil-opp.com/testing/
            qemuExitPortHex = "0xf4";
          in
          [
            rec {
              networking.hostName = hostName;
              virtualisation.vmVariant = {
                virtualisation = {
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
                  diskSize = 2 * 1024; # Megabytes
                  # This seems to speed up boot a bit.
                  cores = 8;
                };
              };
              boot.tmp.useTmpfs = true;
              # As an easy way to be able to run it from the kernel cmdline, just
              # encode the benchmark into a systemd service. You can then run it
              # with systemd.unit=kbn-guest.service
              systemd.services.kbn-guest = {
                script =
                  let
                    outDir = virtualisation.vmVariant.virtualisation.sharedDirectories.ktests-output.target;
                  in
                  ''
                    # Writing the value v to the isa-debug-exit port will cause QEMU to
                    # immediately exit with the exit code `v << 1 | 1`.
                    ${lib.getExe wrappedProg} --out-dir /mnt/kbn-output \
                      || ${pkgs.ioport}/bin/outb ${qemuExitPortHex} $(( $? - 1 ))
                  '';
                serviceConfig = {
                  Type = "oneshot";
                  StandardOutput = "tty";
                  StandardError = "tty";
                };
                onSuccess = [ "poweroff.target" ];
                after = lib.optional requiresInternet "network-online.target";
                wants = lib.optional requiresInternet "network-online.target";
              };
              boot.kernelParams = [ "systemd.unit=kbn-guest.service" ];
              # Don't bother storing logs to disk, that seems like it will just
              # occasionally lead to unnecessary slowdowns for log rotation and
              # stuff.
              services.journald.storage = "volatile";
            }
          ] ++ nixosModules;
      };
      # This is the "official" entry point for running NixOS as a QEMU guest, we'll
      # wrap this.
      nixosRunner = nixosConfig.config.system.build.vm;
    in
    pkgs.writeShellApplication {
      name = "${name}-in-vm";
      text = ''
        # TODO: Set this properly
        export KBN_OUTPUT_HOST=/tmp/kbn_guest_output
        mkdir -p "$KBN_OUTPUT_HOST"
        ${nixosRunner}/bin/run-${hostName}-vm
      '';
      passthru = { inherit nixosConfig; };
    };
}
// passthru
// { inherit requiresInternet; }
