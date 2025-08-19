{
  config,
  self,
  lib,
  ...
}:
{
  config = {
    warnings =
      let
        # Can't easily set this here since we need information from the flake
        # (it would require specialArgs or something). So we just validate it's
        # set and tell the user to set it themselves.
        revWarnings = lib.optional (config.system.configurationRevision == null) ''
          You probably want to set system.configurationRevision so that you
          can tell which version of the flake it was built from. Try adding
          this to the `modules` argument of nixpkgs.lib.nixosSystem in your
          flake.nix:

              system.configurationRevision = self.rev or "dirty";
        '';
        # For this one we can't know what the user would want to put here so
        # just check they set something.
        variantWarnings = lib.optional (config.system.nixos.variant_id == null) ''
          You should set system.nixos.variant_id to a symbolic name for the
          variant of the system (it should uniquely identify it among
          configurations that can be built from the current revision of your
          flake). This will be used to identify it when comparing results.
        '';
      in
      revWarnings ++ variantWarnings;
  };
}
