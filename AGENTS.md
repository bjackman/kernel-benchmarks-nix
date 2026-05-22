# AGENTS.md

This is a polyglot project, Nix is used as the glue. Per-language tooling will
probably not be available "natively" on the host, for example instead of using
Cargo directly for Rust code you will need to build/run the relevant Nix
derivation. This a flake project so you will want to use the `nix` CLI instead
of stuff like `nix-build`.

For example to build the secretmem-vs-frag benchmark run
`nix build .#benchmarks.x86_64-linux.secretmem-vs-frag`. If for some reason you
need to directly run Cargo commands you would use
`nix develop .#benchmarks.x86_64-linux.secretmem-vs-frag -c cargo <command>`.

Before committing, use `nix fmt` to format the code. If you added code in a new
language you might need to update the `treefmt` config in `flake.nix`. Also
ensure `nix flake check` is clean. Eventually we will need to run
`nix run .#impure-tests`, but this can take a very long time so don't do this
automatically, only after consulting with the user.
