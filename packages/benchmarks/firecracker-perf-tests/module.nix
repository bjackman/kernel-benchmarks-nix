{ pkgs, ... }:
{
  # The firecracker devenv is based on Docker.
  virtualisation.docker = {
    enable = true;
    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };
}
