{
  pkgs,
  run-benchprog,
  ...
}:
# Tip: to debug this, run nix run
# .#checks.x86_64-linux.run-benchprog-integration.driverInteractive which will
# drop you in a Python REPL. You can then run the Python code below. You can
# then run client.shell_interact() to get a shell on the client machine for
# example.
pkgs.testers.nixosTest {
  name = "run-benchprog-integration";

  nodes = {
    client =
      { pkgs, ... }:
      {
        environment.systemPackages = [ run-benchprog ];
      };

    target =
      { pkgs, ... }:
      {
        services.openssh.enable = true;
        services.openssh.settings.PermitRootLogin = "yes";
      };
  };

  testScript = ''
    start_all()
    target.wait_for_unit("sshd.service")
    target.wait_for_open_port(22)

    # Setup SSH keys
    client.succeed("ssh-keygen -t ed25519 -N \"\" -f /root/.ssh/id_ed25519")
    key = client.succeed("cat /root/.ssh/id_ed25519.pub").strip()
    target.succeed(f"mkdir -p /root/.ssh && echo '{key}' > /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys")

    # Accept host key
    client.succeed("ssh -o StrictHostKeyChecking=accept-new root@target echo ok")

    # Run the benchprog with instruments from client against target
    client.succeed("mkdir -p /root/falba-db")
    client.succeed("run-benchprog --falba-db /root/falba-db --instruments vmstat --instruments nixos --no-copy root@target hello-world")

    # Verify the falba db entry on the client
    client.succeed("ls /root/falba-db/hello-world:*/artifacts/instrumentation/vmstat/before")
    client.succeed("ls /root/falba-db/hello-world:*/artifacts/instrumentation/vmstat/after")
    client.succeed("ls /root/falba-db/hello-world:*/artifacts/instrumentation/nixos/nixos-version.json")
  '';
}
