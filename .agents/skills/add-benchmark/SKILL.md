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

If it is _not_ expected to work then run it via
`nix run .#packages.x86_64-linux.impure-tests.$benchname`.

### Adding Falba Parsers

Benchmarks in this repository can integrate with **Falba**, a metric parsing and
database storage framework. To allow Falba to extract metrics from your
benchmark's output files (artifacts):

1.  **Create a Parser Definition (`falba-parsers.nix`)**: In your benchmark
    directory (e.g. `packages/benchmarks/$name/`), create a `falba-parsers.nix`
    file. This file must define one or more parsers under a top-level `parsers`
    attribute.
    - **Simple Static Parsers (e.g., `jsonpath` type)**: If you are parsing
      structured JSON artifacts and don't need external C utilities, define a
      static attribute set:

      ```nix
      {
        parsers.my_metric_name = {
          type = "jsonpath";
          artifact_regexp = "path/to/artifact/.*\\.json";
          jsonpath = "$.nested.metric.value";
          metric = {
            name = "my_metric_name";
            type = "float"; # int, float, string
            unit = "ms";    # optional
          };
        };
      }
      ```

    - **Dynamic/Command Parsers (e.g., `command` type)**: If you need to execute
      helper commands (like `gawk`, `yq`, or `jq`) to parse text/YAML/JSON,
      define it as a Nix function so you can inject dependencies:
      ```nix
      { pkgs, ... }:
      {
        parsers.my_custom_metric = {
          type = "command";
          artifact_regexp = "path/to/output/file";
          args = [
            "${pkgs.gawk}/bin/gawk"
            "/'pattern' { print $2 }"
          ];
          metric = {
            name = "my_custom_metric";
            type = "int";
          };
        };
      }
      ```

2.  **Expose Parsers in `default.nix`**: Update your benchmark's `default.nix`
    to expose the evaluated parser JSON through `passthru`. The central flake
    automatically collects any packages exposing `falba-parsers-json` and
    aggregates them into the environment.

    Add the following to your `wrapBenchmark` arguments:

    ```nix
    wrapBenchmark {
      inherit name;
      rawBenchmark = ...;

      passthru = rec {
        # Import/Evaluate the parser definitions.
        # Use pkgs.callPackage if the file is a function taking pkgs,
        # otherwise use standard import.
        falba-parsers = pkgs.callPackage ./falba-parsers.nix { };
        # Or: falba-parsers = import ./falba-parsers.nix;

        # Write the parser set to a JSON store path.
        falba-parsers-json = pkgs.writers.writeJSON "falba-parsers.json" falba-parsers;
      };
    }
    ```

After adding the parser, run `nix develop` to verify that your new metrics are
recognized in the local environment (they will be aggregated into the path
defined by `FALBA_PARSERS_PATH` environment variable).
