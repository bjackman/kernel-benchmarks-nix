---
name: add-benchmark
description: Add a new benchmark to the repository
---

This essentially involves:

- Creating a Nix derivation for the actual benchmark executable.
- Wrapping it for kernel-benchmarks-nix using the `wrapBenchmark` helper. This
  will produce a "package" as in a thing that eventually gets passed to Nix's
  `callPackage`.
- Plumbing it into the rest of the flake.

Create the package as `packages/benchmarks/$name/default.nix` which should be a
Nix package, for example:

```nix
{
  pkgs,
  lib,
  inputs,
  wrapBenchmark,
  ...
}:
let
  name = "stress-ng";
in
wrapBenchmark {
  inherit name;
  rawBenchmark = <main benchmark derivation>;
}
```

Next, add the new benchmark to the
benchmarks.${system} output in `flake.nix`.
`git add` the new file, then ensure it builds by running `nix build
.#benchmarks.x86_64-linux.$name`.

By default, `wrapBenchmark` will add a flake check to run the benchmark. If the
benchmark isn't expected to work from within the Nix sandbox, read
`lib/wrapBenchmark.nix` to understand what options are available to encode this
limitation and add an alternative method for testing the benchmark.

If the benchmark _is_ expected to work in the Nix sandbox, check this by running
`nix build .#checks.x86_64-linux.$benchname`. Once that is passing, also check
the overall `nix flake check`.

If it is _not_ expected to work then run it via `nix run .#packages.x86_64-linux.impure-tests.$benchname`.