# Proposal: Support Stressors in run-benchprog (Revised V3)

We propose adding support for running stressors in parallel with benchmarks in
`run-benchprog`. This will allow investigating benchmark performance under
various resource contention scenarios.

## Approach

### 1. Stressor Registry

We will introduce a `stressors` registry in `flake.nix`, similar to `benchmarks`
and `instruments`.

```nix
# In flake.nix
stressors.${system} = {
  secretmem = pkgs.callPackage ./packages/stressors/secretmem { };
};
```

Each stressor will be a package that outputs an executable supporting `--start`
and `--stop` commands.

```nix
# In packages/stressors/secretmem/default.nix
{ pkgs, ... }:
pkgs.writeShellApplication {
  name = "stress-secretmem";
  runtimeInputs = [ pkgs.stress-ng ];
  text = ''
    PID_FILE="$KBN_STRESSOR_DIR/stressor.pid"
    STATUS_FILE="$KBN_STRESSOR_DIR/status.json"

    case "$1" in
      --start)
        echo '{"stressed": true}' > "$STATUS_FILE"
        # Run in background, redirect FDs to avoid hanging SSH, and disown.
        nohup stress-ng --secretmem 0 >/dev/null 2>&1 &
        echo $! > "$PID_FILE"
        ;;
      --stop)
        if [[ -f "$PID_FILE" ]]; then
          pid=$(cat "$PID_FILE")
          kill "$pid" || true
          wait "$pid" 2>/dev/null || true
          rm "$PID_FILE"
        fi
        ;;
      *)
        echo "Usage: $0 {--start|--stop}"
        exit 1
        ;;
    esac
  '';
  passthru = {
    falba-parsers.parsers.stressed_secretmem = {
      type = "command";
      artifact_regexp = "stressors/secretmem/status.json";
      args = [
        "${pkgs.jq}/bin/jq"
        ".stressed"
      ];
      fact = {
        name = "stressed_secretmem";
        type = "bool";
        default = "false";
      };
    };
    falba-parsers-json = pkgs.writers.writeJSON "falba-parsers.json" {
      parsers = falba-parsers.parsers;
    };
  };
}
```

### 2. Command Line Interface

We will add a `--stressor` option to `run-benchprog`.

```bash
run-benchprog --target user@host --benchprog my-bench --stressor secretmem
```

The `--stressor` argument will refer to a key in the `stressors` registry.

### 3. Implementation in `run-benchprog.sh`

- **Registry Integration**: `run-benchprog` will receive
  `STRESSOR_REGISTRY_JSON` env var.
- **Argument Parsing**: Add `--stressor` to `getopt` and parse it.
- **Validation**: Validate that the requested stressor exists in the registry.
- **Stressor Lifecycle**:
  - **Setup**: If a stressor is active, copy its executable (resolved from
    registry) to the target, unless `--no-copy` is specified.
    - Create a remote directory for the stressor:
      `remote_stressor_dir=$(do_ssh mktemp -d)`
  - **Start**: Before running instruments (`--before`), start the stressor.
    - `do_ssh "KBN_STRESSOR_DIR=$remote_stressor_dir $stressor_executable --start"`
  - **Instruments Setup**: Run instruments `--before`.
  - **Run Benchmark**: Run the benchmark.
  - **Instruments Teardown**: Run instruments `--after`.
  - **Stop**: After instruments teardown, stop the stressor.
    - `do_ssh "KBN_STRESSOR_DIR=$remote_stressor_dir $stressor_executable --stop"`
  - **Collect**: Pull the stressor directory to the host.
    - `do_rsync_pull "$remote_stressor_dir/" "$collected_files_dir/stressors/$STRESSOR/"`
    - Clean up remote stressor directory: `do_ssh "rm -rf $remote_stressor_dir"`

### 4. Dependency Management

- Stressor dependencies are handled transparently by the Nix package definition
  of the stressor itself.
- `run-benchprog` will copy the stressor executable and its dependencies to the
  target using `nix copy` (unless `--no-copy` is specified).

### 5. Falba Integration

- Update `flake.nix` to include `run-benchprog` and the active stressors in
  `falba-parsers` assembly.
  ```nix
  # In flake.nix
  allProviders = lib.filterAttrs (_: p: p ? falba-parsers-json) (
    self.benchmarks.${system} //
    self.instruments.${system} //
    self.stressors.${system} //
    { inherit run-benchprog; }
  );
  ```

## Test Coverage

### Integration Test

We will extend `packages/run-benchprog/integration-test.nix`:

1.  Add a test case that runs `hello-world` with `--stressor secretmem`.
2.  Verify that `stressors/secretmem/status.json` is created and contains
    `"stressed": true`.

### Verifying Falba Facts

We will verify that the `stressed_secretmem` fact is correctly imported into the
Falba database.
