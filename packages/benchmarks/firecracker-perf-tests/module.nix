{ pkgs, ... }:
{
  imports = [ ../../../modules/benchprog-support.nix ];

  # The firecracker devenv is based on Docker. In rootless mode there are
  # permissions errors, we just need to deal with the fact that it leaves behind
  # files owned by root.
  virtualisation.docker.enable = true;

  virtualisation.vmVariant = {
    # The firecracker devtool will allocate 48G of 2M hugepages which is really
    # slow in a VM.
    # Attempts to fix this:
    # This just causes VM boot to be really slow:
    # boot.kernelParams = [ "hugepagesz=2M" "hugepages=24552"];
    # This causes the docker process to crash (presumably getting OOMed, I
    # suspect because there is basically no memory available for normal non-huge
    # pages or something):
    # boot.kernelParams = [ "hugepagesz=1G" "hugepages=48"];
    # After chatting to Frank van der Linden I realised it's probably a bug that
    # allocating those hugepages takes so long anyway.

    virtualisation = {
      # Need to download container images, big disk when testing in a VM plz.
      diskSize = 16 * 1024; # Megabytes
      # Also this is a big workload, much RAM
      memorySize = 64 * 1024;
    };
  };
}
