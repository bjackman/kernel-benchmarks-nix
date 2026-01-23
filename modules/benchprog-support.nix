# Stuff to set in your test machine's configuration in order to make the basic
# benchmarking infrastructure work.
# This should be imported by all the benchmark-specific modules.
{ self, ...  }:
{
  config = {
    # Record the version of the flake, this will then be available
    # from the `nixos-version` command.
    system.configurationRevision = self.rev or "dirty";
  };
}
