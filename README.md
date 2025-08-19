# ASI Benchmarks

This is the beginning of untangling of the mess in [this
repo](https://github.com/bjackman/nixos-flake) where I was simultaneously
learning Nix and developing a bunch of janky scripts for benchmarking ASI.

The goal is to pick stuff apart here to get something like that but reusable and
comprehensible. It's not there yet.

## Components

- Each benchmark is a Nix package. Either defined in `packages/benchmarks` or
  directly taken from Nixpkgs.

- This is wrapped by an internal`run-benchmarks`. This gives the raw benchmarks
  a simpler and more uniform interface, but isn't designed to be used directly.

  JANK: It kinda looks like a general framework for this, but it's actually an
  idiotic bash script with hard-coded logic, and the packaging also has
  hard-coded references to specific benchmarks.

- This is _further_ wrapped by `benchmarks-wrapper` which is designed to
  actually be used directly if so desired. This takes care of running
  `run-benchmarks`, if necessary after booting a VM for you and deploying it
  there.

  JANK: This expects its host system to have a NixOS QEMU script installed and
  available as `run-nixos-vm`. This was a hack during development that never got
  eliminated. Instead this should be a parameter of the package.

  JANK: WTF are these names lol

  JANK: This has some logic for "instrumentation" but actually it just supports
  calling a single hard-coded `bpftrace` script that measures some specific
  stuff I cared about.

- `deploy-config` provides a default idiotic script for deploying a NixOS
  configuration to a host over SSH. This is currently UNTESTED.

- `benchmark-configs` is the main entry point th is the main entry point for
  running benchmarks. You run it on your local development machine and it
  deploys configs, runs benchmarks on them, and fetches result data.

- A NixOS module called `benchmark-support.nix` which is supposed to deal with
  any parts of the benchmarking logic that are coupled to the system config.
  In practice this currently just validates stuff and tells you to set it
  yourself.