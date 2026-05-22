{
  pkgs,
  lib,
  inputs,
  wrapBenchmark,
  ...
}:
let
  name = "secretmem-vs-frag";
  rawBenchmark = pkgs.rustPlatform.buildRustPackage {
    pname = name;
    version = "0.1.0";
    src = ./.;
    cargoHash = "sha256-JuZIyOUJdFfGWutZjls6HY/O6eQF2yGrNdLoU+D0LNQ=";

    meta.mainProgram = name;
  };
in
wrapBenchmark {
  inherit name rawBenchmark;
  # Running this benchmark on a big host is pretty slow, and it needs to be able
  # to genuinely exhaust its host's memory (exhausting a cgroup is not enough),
  # so for testing it we will just run it in a VM. We can make wrapBenchmark do
  # that by providing a NixOS module, which we can also use to configure the
  # size of the VM.
  nixosModules = [
    ({
      virtualisation.vmVariant.virtualisation.memorySize = 1024; # MiB
      # When running in systemd, prevent the entire service from getting
      # OOM-killed, since we want just one specific subprocess to die.
      systemd.services.kbn-guest.serviceConfig.OOMPolicy = "continue";
    })
  ];
}
