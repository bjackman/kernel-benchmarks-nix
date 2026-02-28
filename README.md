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

## NOTES: Design

I think the actual design I want here is:

- A standard interface for running a single-node benchmark locally. It has flags
  like `--iterations`, `--out-dir` and `--instrumentation`. Call this a
  `benchprog`. Later, benchprogs probably accept parameters.

  See `packages/benchmarks/firecracker-perf-tests` for an example that wraps
  some janky stuff in a janky way, but then produces something with a standard
  interface.

  TODO: This needs to be split up into phases, probably just "setup" and "run"
  initially.
- For each benchprog, an optional NixOS module that provides the hard
  dependencies on the system for running the prog.

  TODO: Need a way to register these and expose them conveniently to the user.
  Also a way to check if the user has forgotten to import the relevant module.
- For each benchprog, some logic to parse artifacts into FALBA.

  TODO: Also need a way to register and expose these.
- Some helper scripts for wrapping workloads into benchprogs.
- A tool that takes a benchprog, plus its NixOS module if there is one, and
  produces a new benchprog that runs the original one in a NixOS VM.

  As well as benchmarking VM guest performance, this tool can be used for
  "integration testing" the benchmarks.
- Some basic scripts for deploying NixOS configs, running benchprogs [remotely]
  and fetching their results into a FALBA DB.

  `run-benchprog` runs it over SSH.

How would this extend to multi-node benchmarks? No idea.

I think it's fine to design this with the assumption that the system is a pretty
"proper computer" with SSH and stuff.

The user will take care of building the actual host system themselves.

The user will need to make sure that their SSH user can do sudo without a
password. Or, perhaps there should be a "base" NixOS module that creates a user
for use by KBN?

At first, this can all just be janky shell scripts, the important thing is the
interfaces between them. Later it might make sense to port some parts to Go.

TODOS: (Many of these are duplicated as comments elsewhere):

- NEXT: Make `nix run .#benchmarks.x86_64-linux.firecracker-perf-tests.in-vm` work.
- Package something like the above into "tests" (nix flake check for ones that
  require no network, boring old packages for the rest).

  (I can't remember why I was working on this, but somehow it should help with
  the next step).
- Figure out how to expose the relevant derivations to a user's devShell
  - First, support running benchmarks without needing to provide their
    flakeref/store path.
  - Eventually, should offer a way for the user to add their own
    benchmarks/instruments when they instantiate the package.
  - With the above done, perhaps we want to drop the ability to just pass in a
    random binary run-benchprog.
- Figure out how to expose the Falba parser stuff
  - One challenge here is that we want instrumentation/benchmarks to be very
    promiscuous about what artifacts they capture, and we want them to provide as
    much logic as possible to parse the stuff that's easy to parse. But, we don't
    wan't to overwhelm the user's Falba DB with a bunch of metrics they don't care
    about. So we need to give them a way to adopt subsets of the parsing logic.
- Figure out how to expose the instrumentation stuff
- Split up benchmark running into phases
- Start porting some bits to a proper programming language?
- Figure out how to do instrumentation processing offline with a better API in
  Falba. At the moment it's being done on the target host which is dumb.
- Add the other missing elements from the elements listed above
- Clean up naming a bit.
- Figure out how to paramaterise benchprogs
- Add a flake template
- Define what a "benchprog" is and what a "benchmark" is, then clean up
  nomenclature in the codebase. I think this requires more experience with
  actually packaging benchmarks though.