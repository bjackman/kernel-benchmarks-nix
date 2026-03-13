{ pkgs, ... }:
{
  imports = [ ../../../modules/benchprog-support.nix ];

  # The firecracker devenv is based on Docker. In rootless mode there are
  # permissions errors, we just need to deal with the fact that it leaves behind
  # files owned by root.
  virtualisation.docker.enable = true;

  # Need to download container images, big disk when testing in a VM plz.
  virtualisation.vmVariant.virtualisation.diskSize = 16 * 1024; # Megabytes
}
