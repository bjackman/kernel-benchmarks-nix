{
  pkgs,
  lib,
  inputs,
  self,
}:
# This produces a version of the benchmark that gets run in a NixOS VM. The
# purposes of this are a) for benchmarking a host's performance as a
# hypervisor and b) for integration-testing the benchmark script.
# However, it's possible this is dumb: for a) maybe the idea of running random
# benchmarks in an arbitrary VMM is as silly way to benchmark. For b) maybe
# NixOS VM tests would be more suitable.{
{
  name,
  wrappedProg,
  nixosModules,
  requiresInternet,
  worksInNixSandbox,
}:
let
  hostName = "testvm-${name}";
  nixosConfig = inputs.nixpkgs.lib.nixosSystem {
    system = pkgs.stdenv.hostPlatform.system;
    specialArgs = { inherit self; };
    modules = [
      ../vm-base-module.nix
      (
        { config, ... }:
        {
          networking.hostName = hostName;

          # As an easy way to be able to run it from the kernel cmdline, just
          # encode the benchmark into a systemd service. You can then run it
          # with systemd.unit=kbn-guest.service
          systemd.services.kbn-guest = {
            script = ''
              set +e
              declare -a kbn_args_arr=()
              if [ -n "''${KBN_ARGS:-}" ]; then
                  read -a kbn_args_arr <<< "$KBN_ARGS"
              fi

              ${lib.getExe wrappedProg} --out-dir /mnt/kbn-output -- "''${kbn_args_arr[@]}"
              echo $? > /run/kbn-exit-code
            '';
            # Put all the stuff that a normal NixOS system has into the
            # systemd service environment, to make testing more practical.
            # Use systemPackages instead of corePackages so that stuff
            # installed by the benchmark's NixOS module is also visible.
            path = config.environment.systemPackages;
            serviceConfig = {
              Type = "oneshot";
              StandardOutput = "tty";
              StandardError = "tty";
              CacheDirectory = "kbn-guest";
            };
            unitConfig = {
              SuccessAction = "poweroff";
              FailureAction = "poweroff";
            };
            after = [ "multi-user.target" ] ++ lib.optional requiresInternet "network-online.target";
            wants = [ "multi-user.target" ] ++ lib.optional requiresInternet "network-online.target";
          };
        }
      )
    ]
    ++ nixosModules;
  };
  # This is the "official" entry point for running NixOS as a QEMU guest, we'll
  # wrap this.
  nixosRunner = nixosConfig.config.system.build.vm;
in
pkgs.writeShellApplication {
  name = "${name}-in-vm";
  runtimeInputs = [ pkgs.getopt ];
  runtimeEnv = {
    KBN_VM_RUNNER = "${nixosRunner}/bin/run-${hostName}-vm";
  };
  text = builtins.readFile ./run-in-vm.sh;
  passthru = { inherit nixosConfig requiresInternet worksInNixSandbox; };
}
