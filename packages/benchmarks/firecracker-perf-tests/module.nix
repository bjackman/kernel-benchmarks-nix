{ pkgs, ... }:
{
  imports = [ ../../../modules/benchprog-support.nix ];

  # The firecracker devenv is based on Docker. In rootless mode there are
  # permissions errors, we just need to deal with the fact that it leaves behind
  # files owned by root.
  virtualisation.docker.enable = true;

  virtualisation.vmVariant.virtualisation = {
    # Need to download container images, big disk when testing in a VM plz.
    diskSize = 16 * 1024; # Megabytes
    # Also this is a big workload, much RAM
    memorySize = 32 * 1024;
  };
}
