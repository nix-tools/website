+++
date = '2025-04-10T11:31:54Z'
title = 'Deploying a Rust web service on NixOS'
+++

I have a small Rust web service that serves HTTP on a port.

In order to run this in production, I want to

- compile and install the web service binary on my server,
- run it as a non-interactive user on a local port, and
- expose the web service via an nginx reverse proxy

I will use a subdirectory of an already existing website, such as a [Hugo
static website](/articles/hugo-static-site-setup).

## A web service package derivation

In order to build and package my project, I need to express a derivation.

The simplest place to do this is default.nix, so that's what I will do.

I know that I should be using `pkgs.rustPlatform.buildRustPackage` because I
recall its name. But I also want to practice and demonstrate as many generally
useful techniques in Nix, and I want to understand what it does by building the
derivation from scratch and see what problems I get.

For the sake of simplicity, this is not a [Cargo Workspace][cargo-ws], but
instead a single crate in a git repository:

- https://github.com/sshine/axum-forum

[cargo-ws]: https://doc.rust-lang.org/book/ch14-03-cargo-workspaces.html
[axum-forum-git]: https://github.com/sshine/axum-forum

My first default.nix therefore looks like:

```nix
{ pkgs ? import <nixpkgs> {} }:
let
  # Deriving properties from Cargo.toml means there is a single source of truth.
  cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
in
pkgs.stdenv.mkDerivation rec {
  # Specifying `pname` and `version` derives `name` as "{pname}-{version}"
  pname = "axum-forum";
  version = cargoToml.package.version;
  src = ./.;

  # Installing rustup from nixpkgs also installs cargo and rustc shims
  buildInputs = [
    pkgs.rustup
  ];

  buildPhase = ''
    cargo build
  '';
}
```

Trying `nix-build` I immediately get problems:

```
Running phase: buildPhase
error: could not create home directory: '/homeless-shelter/.rustup': Permission denied (os error 13)
error: builder for '/nix/store/5z875zd45044gw8zmv8rl7wpf4dkpl4f-axum-forum-0.1.0.drv' failed with exit code 1;
       last 9 log lines:
       > Running phase: unpackPhase
       > unpacking source archive /nix/store/psb951v45d8prygvxa633sr6a0d6qgzh-axum-forum
       > source root is axum-forum
       > Running phase: patchPhase
       > Running phase: updateAutotoolsGnuConfigScriptsPhase
       > Running phase: configurePhase
       > no configure script, doing nothing
       > Running phase: buildPhase
       > error: could not create home directory: '/homeless-shelter/.rustup': Permission denied (os error 13)
       For full logs, run 'nix log /nix/store/5z875zd45044gw8zmv8rl7wpf4dkpl4f-axum-forum-0.1.0.drv'.
```

This is because `rustup` needs to bootstrap the toolchain dynamically. This
works inside a shell.nix dev shell, but it does not work when running
`nix-build`, since a build process that performs arbitrary online activity
cannot easily be reproducible.

I could instead try to make sure `cargo` and `rustc` are installed, rather than
offload this to `rustup`:

```nix
buildInputs = [
  pkgs.rustc
  pkgs.cargo
];
```

Now `rustup` does not try to download `cargo`, but `cargo` still tries, not
unreasonably, to download dependencies:

```
Running phase: buildPhase
    Updating crates.io index
warning: spurious network error (3 tries remaining): [6] Could not resolve hostname (Could not resolve host: index.crates.io)
warning: spurious network error (2 tries remaining): [6] Could not resolve hostname (Could not resolve host: index.crates.io)
warning: spurious network error (1 tries remaining): [6] Could not resolve hostname (Could not resolve host: index.crates.io)
error: failed to get `axum` as a dependency of package `axum-forum v0.1.0 (/build/axum-forum)`
```

But this relies on non-reproducible network activity at an arbitrary point in the build process.

Let's bite the bullet and do something with fewer lines, but more machinery:

```nix
{ pkgs ? import <nixpkgs> {} }:
let
  cargoToml = builtins.fromTOML (builtins.readFile ./Cargo.toml);
in
pkgs.rustPlatform.buildRustPackage rec {
  pname = "axum-forum";
  version = cargoToml.package.version;
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
}
```

The [`buildRustPackage`][build-rust-package-doc] documentation is a little brief.

To see what it actually does, it may be necessary to look at the source code [`build-rust-package/default.nix`][build-rust-package-nix].

Specifying `cargoLock.lockFile` will retrieve the dependencies using fixed-output derivations from that lockfile.

...

[build-rust-package-doc]: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/rust.section.md#buildrustpackage-compiling-rust-applications-with-cargo-compiling-rust-applications-with-cargo
[build-rust-package-nix]: https://github.com/NixOS/nixpkgs/blob/master/pkgs/build-support/rust/build-rust-package/default.nix

```
[feng:~/Projects/nursery/axum-forum] [main] $ nix-build
this derivation will be built:
  /nix/store/4ljvidm0xw2pskdmgb9scq3n3la7r3fv-axum-forum-0.1.0.drv
building '/nix/store/4ljvidm0xw2pskdmgb9scq3n3la7r3fv-axum-forum-0.1.0.drv'...
Running phase: unpackPhase
unpacking source archive /nix/store/fd33hm05zi0sl431cxff4xxggkvghp69-axum-forum
source root is axum-forum
Executing cargoSetupPostUnpackHook
Finished cargoSetupPostUnpackHook
Running phase: patchPhase
Executing cargoSetupPostPatchHook
Validating consistency between /build/axum-forum/Cargo.lock and /build/cargo-vendor-dir/Cargo.lock
Finished cargoSetupPostPatchHook
Running phase: updateAutotoolsGnuConfigScriptsPhase
Running phase: configurePhase
Running phase: buildPhase
Executing cargoBuildHook
cargoBuildHook flags: -j 2 --target x86_64-unknown-linux-gnu --offline --profile release
   Compiling proc-macro2 v1.0.93
   Compiling unicode-ident v1.0.16
   Compiling libc v0.2.169
...
   Compiling axum-forum v0.1.0 (/build/axum-forum)
    Finished `release` profile [optimized] target(s) in 3m 51s
Executing cargoInstallPostBuildHook
Finished cargoInstallPostBuildHook
Finished cargoBuildHook
buildPhase completed in 3 minutes 52 seconds
Running phase: checkPhase
Executing cargoCheckHook
cargoCheckHook flags: -j 2 --profile release --target x86_64-unknown-linux-gnu --offline -- --test-threads=2
   Compiling axum-forum v0.1.0 (/build/axum-forum)
    Finished `release` profile [optimized] target(s) in 1.07s
     Running unittests src/main.rs (target/x86_64-unknown-linux-gnu/release/deps/axum_forum-37832ef0ae0ea088)

running 0 tests

test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.00s

Finished cargoCheckHook
Running phase: installPhase
Executing cargoInstallHook
Finished cargoInstallHook
Running phase: fixupPhase
shrinking RPATHs of ELF executables and libraries in /nix/store/l4lgkl7ikb29cjd6s37k8f5g96arlr9z-axum-forum-0.1.0
shrinking /nix/store/l4lgkl7ikb29cjd6s37k8f5g96arlr9z-axum-forum-0.1.0/bin/axum-forum
checking for references to /build/ in /nix/store/l4lgkl7ikb29cjd6s37k8f5g96arlr9z-axum-forum-0.1.0...
patching script interpreter paths in /nix/store/l4lgkl7ikb29cjd6s37k8f5g96arlr9z-axum-forum-0.1.0
stripping (with command strip and flags -S -p) in  /nix/store/l4lgkl7ikb29cjd6s37k8f5g96arlr9z-axum-forum-0.1.0/bin
/nix/store/l4lgkl7ikb29cjd6s37k8f5g96arlr9z-axum-forum-0.1.0
```

And we can see that it produces the service executable:

```
$ result/bin/axum-forum
Listening on http://127.0.0.1:3000
```

## A systemd service derivation

Since the output of the package derivation is just a package, deployment on
NixOS has not been addressed.

We don't want to

- manually log into the NixOS server,
- run `git pull`,
- run `nix-build`, and
- `./result/bin/axum-forum`

every time the service should be updated.

We want to start the service automatically, and to monitor its process.

We can create a NixOS module that can be included in a NixOS configuration.nix.
