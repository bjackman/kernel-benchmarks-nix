# Stuff to set in your test machine's configuration in order to make the basic
# benchmarking infrastructure work.
# This should be imported by all the benchmark-specific modules.
{ self, ... }:
{
  config = {
    # Record the version of the flake, this will then be available
    # from the `nixos-version` command.
    # TODO: No, this requires that we set specialArgs, this is pretty yucky.
    # Probably just wanna go back to this being nothing but a warning.
    system.configurationRevision = self.rev or "dirty";
  };
}
