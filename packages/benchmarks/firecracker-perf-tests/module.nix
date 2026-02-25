{ pkgs, ... }:
{
  imports = [ ../../../modules/benchprog-support.nix ];

  # The firecracker devenv is based on Docker. In rootless mode there are
  # permissions errors, we just need to deal with the fact that it leaves behind
  # files owned by root.
  virtualisation.docker.enable = true;

  # Firecracker's devtool will allocate this many 2M hugepages, to speed that
  # process up just come up with that many in the first place.
  boot.kernelParams = [ "default_hugepagesz=2M" "hugepagesz=2M" "hugepages=24552" ];
}
