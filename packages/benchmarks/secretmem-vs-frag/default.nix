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
    cargoHash = "sha256-Fy1LI8LVk702fElA+S1+jSWUgQV7I/Up6F5+xcqZGu4=";

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
      # Disable systemd-oomd because it kills the whole service cgroup on high
      # memory pressure, preventing our runner from catching the worker's OOM death.
      # We rely on the kernel OOM killer instead, which respects oom_score_adj.
      systemd.oomd.enable = false;
    })
  ];

  integrationTests = {
    baseline = {
      args = [ ];
    };
    antagonized = {
      args = [ "--antagonize" ];
    };
  };
  passthru = rec {
    falba-parsers = import ./falba-parsers.nix;
    falba-parsers-json = pkgs.writers.writeJSON "falba-parsers.json" falba-parsers;
  };
}
