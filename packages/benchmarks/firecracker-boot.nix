{
  pkgs,
  # This is the library function provided by the nixpkgs flake. It needs to be
  # passed in as a package arg. This is probably stupid, there is probably a way
  # to generate the configuration directly from something availble in pkgs.
  nixosSystem,
  firecracker,
  ...
}:
let
  guestConfig = nixosSystem {
    system = "x86_64-linux";
    modules = [
      ({
        # These are in megabytes.
        virtualisation.vmVariant.virtualisation.memorySize = 2 * 1024;
        virtualisation.diskSize = 16 * 1024;

        fileSystems."/" = {
          device = "/dev/disk/by-label/NIXOS";
          fsType = "ext4";
          neededForBoot = true;
        };
        # Avoid warnings due to building an incomplete image
        boot.loader.grub.enable = false;
        boot.initrd.kernelModules = [
          "virtio_pci"
          "virtio_blk"
        ];
        # Weird hack, for some reason setting noCheck doesn't actually disable
        # fsck in the initrd?
        boot.initrd.checkJournalingFS = false;
      })
    ];
  };
  ext4Image = pkgs.callPackage "${pkgs.path}/nixos/lib/make-ext4-fs.nix" ({
    storePaths = [ guestConfig.config.system.build.toplevel ];
    volumeLabel = "NIXOS";
  });
  firecrackerConfig = {
    boot-source = {
      # Seems Firecracker requires an uncompressed kernel.
      kernel_image_path = "${guestConfig.config.system.build.kernel.dev}/vmlinux";
      boot_args = "console=ttyS0 reboot=k panic=1";
      initrd_path = "${guestConfig.config.system.build.initialRamdisk}/initrd";
    };
    drives = [
      {
        drive_id = "rootfs";
        is_root_device = true;
        cache_type = "Unsafe";
        is_read_only = true;
        path_on_host = ext4Image;
      }
    ];
  };
  firecrackerJson = pkgs.writeText "firecracker.json" (builtins.toJSON firecrackerConfig);
in
pkgs.writeShellApplication {
  name = "firecracker-boot";
  runtimeInputs = [ firecracker ];
  text = ''
    # Seems the API socket is mandatory
    tmpdir=$(mktemp -d)
    firecracker --api-sock "$tmpdir"/firecracker.sock --enable-pci --config-file ${firecrackerJson}
  '';
}
# Hang intermediate targets on the output so they can be built for debug inspection.
// {
  inherit guestConfig ext4Image firecrackerJson;
}
