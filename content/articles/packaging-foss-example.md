+++
date = '2025-04-07T13:33:50Z'
title = 'Packaging open-source projects with Nix'
draft = false
+++

## Introduction

**Problem:** You run NixOS and want to download, compile and run some project on GitHub.

While most projects come with a README that tell you what packages to `apt-get install`
if you run Ubuntu, they often don't explain how to do the same on NixOS. This
makes NixOS a harder Linux distro to use, because you need to be able to write
Nix to run certain programs.

Here are some ways of increasing difficulty to make a package available on NixOS:

- A shell.nix to simply get started
- A default.nix for later bundling
- A flake.nix for making it quickly installable
- A package.nix for inclusion into nixpkgs

## Example: Schemesh

A project called [schemesh](https://github.com/cosmos72/schemesh/) was
[featured on hacker news](https://news.ycombinator.com/item?id=43061183), and I
wanted to try it out.

It's written in Chez Scheme, uses Makefile, and
makes use of [a bunch of libraries](https://github.com/cosmos72/schemesh#build-instructions).

I need to install those to get anywhere.

## shell.nix

Rather than install those dependencies globally on my system, I can create a file called shell.nix:

```nix
{ pkgs ? import <nixpkgs> {} }:
  pkgs.mkShell {
    packages = [
      pkgs.chez
      pkgs.lz4
      pkgs.ncurses
      pkgs.libuuid
      pkgs.zlib
    ];
  }
```

Guessing what the libraries are called in nixpkgs can be a challenge, but you can use https://search.nixos.org.

I can now try to compile schemesh in a `nix-shell` using `make -j` which Schemesh'es README says to use:

```sh
$ nix-shell
[nix-shell:~/Projects/schemesh] $ make -j prefix=$PWD
...
cc -o schemesh main.o ...
cc -o schemesh_test ...
./schemesh_test
compiling libschemesh.ss with output to libschemesh_temp.so
all 570 tests passed

[nix-shell:~/Projects/schemesh]$ ./schemesh
schemesh: Exception in load: failed for /home/sshine/Projects/schemesh/lib/schemesh/libschemesh_0.8.3.so: no such file or directory
schemesh: Exception in load: failed for /usr/local/lib/schemesh/libschemesh_0.8.3.so: no such file or directory
schemesh: Exception in load: failed for /usr/lib/schemesh/libschemesh_0.8.3.so: no such file or directory
```

I've actually run `make -j prefix=$PWD` with `$PWD` being the working directory I'm in.

Most often the `$prefix` will default to `/usr/local`.

I don't want to install the executable there, but more importantly in this case:

I don't want to install the shared libraries there, either.

This project seems to dynamically load a library after it starts, one that isn't mentioned in `ldd schemesh`:

```sh
$ ldd schemesh
        linux-vdso.so.1 (0x00007f97bfa53000)
        libncursesw.so.6 => /nix/store/x9lgx9pd242kw0sdvdmwvmgj6igw8h8k-ncurses-6.4.20221231/lib/libncursesw.so.6 (0x00007f97bf9d6000)
        libdl.so.2 => /nix/store/81mi7m3k3wsiz9rrrg636sx21psj20hc-glibc-2.40-66/lib/libdl.so.2 (0x00007f97bf9d1000)
        libm.so.6 => /nix/store/81mi7m3k3wsiz9rrrg636sx21psj20hc-glibc-2.40-66/lib/libm.so.6 (0x00007f97bf8e8000)
        libpthread.so.0 => /nix/store/81mi7m3k3wsiz9rrrg636sx21psj20hc-glibc-2.40-66/lib/libpthread.so.0 (0x00007f97bf8e3000)
        libuuid.so.1 => /nix/store/8h9qgd6yp7ld34q6vh1waz5df0d7z3s2-util-linux-minimal-2.39.4-lib/lib/libuuid.so.1 (0x00007f97bf8d9000)
        libc.so.6 => /nix/store/81mi7m3k3wsiz9rrrg636sx21psj20hc-glibc-2.40-66/lib/libc.so.6 (0x00007f97bf600000)
        /nix/store/81mi7m3k3wsiz9rrrg636sx21psj20hc-glibc-2.40-66/lib/ld-linux-x86-64.so.2 => /nix/store/81mi7m3k3wsiz9rrrg636sx21psj20hc-glibc-2.40-66/lib64/ld-linux-x86-64.so.2 (0x00007f97bfa55000)
```

It cannot find this library, because the paths that the dynamic linker inside the executable looks for don't yet contain `libschemesh_0.8.3.so`.

It seems to get fixed when running `make install` (which needs to be told `prefix=$PWD` once again):

```
[nix-shell:~/Projects/schemesh]$ make install prefix=$PWD
[nix-shell:~/Projects/schemesh]$ ./bin/schemesh
shell sshine@machine:~/Projects/schemesh:
```

To make `libschemesh_0.8.3.so` available in `nix-shell` without `make install`, one can also extend `$LD_LIBRARY_PATH` with `$PWD`:

```nix
{ pkgs ? import <nixpkgs> {} }:
  pkgs.mkShell {
    packages = [
      pkgs.chez
      pkgs.lz4
      pkgs.ncurses
      pkgs.libuuid
      pkgs.zlib
    ];

    shellHook = ''
      export LD_LIBRARY_PATH="$PWD:$LD_LIBRARY_PATH"
    '';
  }
```

As a first iteration, this actually works okay.

## default.nix

A shell.nix is great for development, but it can be inconvenient especially for
a compiled project with dynamically linked libraries.

Providing a default.nix will make it possible to:

- patch the executable to fix the library references, instead of with `$LD_LIBRARY_PATH`
- make the `schemesh` binary installable as a NixOS system package

```nix
{ pkgs ? import <nixpkgs> {} }:
let
  # Instead of hardcoding the most recent version of the package in default.nix,
  # a good approach is to extract the version number for the Nix package derivation
  # from somewhere canonical. This way releasing a new version of Schemesh requires
  # updating the version number in fewer places.
  versionLatest =
    builtins.head
      (builtins.match ".*Schemesh Version ([0-9.]+).*"
        (builtins.readFile ./bootstrap/functions.ss));
in
  pkgs.stdenv.mkDerivation {
    name = "schemesh";
    version = versionLatest;
    src = ./.;

    # These are runtime dependencies (also available when building)
    buildInputs = [
      pkgs.chez    # Ubuntu: chezscheme-dev
      pkgs.lz4     # Ubuntu: liblz4-dev
      pkgs.ncurses # Ubuntu: libncurses-dev
      pkgs.libuuid # Ubuntu: uuid-dev
      pkgs.zlib    # Ubuntu: zlib1g-dev
    ];

    # These are build dependencies
    nativeBuildInputs = [
      pkgs.patchelf
    ];

    buildPhase = ''
      make -j prefix=$out
    '';

    installPhase = ''
      mkdir -p $out/bin $out/lib/schemesh

      # Only the executable and the dynamically linked library are copied as outputs
      cp schemesh $out/bin/schemesh
      cp "libschemesh_${versionLatest}.so" $out/lib/schemesh/
      chmod +x $out/bin/schemesh

      # The library paths were broken for some dependencies, presumably because the
      # build system makes incorrect assumptions about the location of .so files on
      # the target system.
      patchelf $out/bin/schemesh --set-rpath \
        "${pkgs.lib.makeLibraryPath [ pkgs.ncurses pkgs.libuuid ]}"
    '';
  }
```

One can now `nix-build` and run the executable:

```sh
$ nix-build
$ ./result/bin/schemesh
shell sshine@machine:~/Projects/schemesh:
```

And better yet, install it:

```sh
{ pkgs, ... }:
let
  schemesh = pkgs.fetchgit {
    url = "https://github.com/cosmos72/schemesh.git";
    rev = "refs/heads/main";
    sha256 = "sha256-2iXCVmm6f8u1QtY8mXZXz+GB4W/a2JFBxSNTkWgiyZU";
  };
in
{
  environment.systemPackages = [
    # ...
    (pkgs.callPackage schemesh {})
  ];
}
```

Having a default.nix is great: We can run a dev shell using `nix-shell`, and we
can `nix-build` and install it into our system.

Ideally we should just be able to write:

```nix
{ pkgs, ... }: {
  environment.systemPackages = [
    pkgs.schemesh
  ];
}
```

## flake.nix

The following is a flake that makes use of the [flake-parts](https://flake.parts) library.

It is a newer alternative to the more widespread flake-utils library, which is [arguably less optimal](https://ayats.org/blog/no-flake-utils).

It combines shell.nix and default.nix, and it adds an "app" which lets you `nix run github:sshine/schemesh`.

```nix
{
  description = "Schemesh - A Unix shell and Lisp REPL, fused together";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs = inputs@{ self, flake-parts, ... }:

    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        # "aarch64-darwin" # does not work
        # "aarch64-linux"  # not tested
        # "x86_64-darwin"  # not tested
      ];

      perSystem = { config, self', inputs', pkgs, system, ... }:
        let
          sharedBuildInputs = [
            pkgs.chez    # Ubuntu: chezscheme-dev
            pkgs.lz4     # Ubuntu: liblz4-dev
            pkgs.ncurses # Ubuntu: libncurses-dev
            pkgs.libuuid # Ubuntu: uuid-dev
            pkgs.zlib    # Ubuntu: zlib1g-dev
          ];

          sharedNativeBuildInputs = [
            pkgs.git
            pkgs.patchelf
          ];

		  versionLatest =
			builtins.head
			  (builtins.match ".*Schemesh Version ([0-9.]+).*"
				(builtins.readFile ./bootstrap/functions.ss));
        in
          {
            packages.default = pkgs.stdenv.mkDerivation {
              name = "schemesh";
              version = versionLatest;
              src = self;

              buildInputs = sharedBuildInputs;
              nativeBuildInputs = sharedNativeBuildInputs;

              buildPhase = ''
                make -j prefix=$out
              '';

              installPhase = ''
                mkdir -p $out/bin $out/lib/schemesh

                cp schemesh $out/bin/schemesh
                cp "libschemesh_${versionFromFile}.so" $out/lib/schemesh/
                chmod +x $out/bin/schemesh

                patchelf $out/bin/schemesh --set-rpath \
                  "${pkgs.lib.makeLibraryPath [ pkgs.ncurses pkgs.libuuid ]}"
              '';
            };

            apps.default = {
              type = "app";
              program = "${self'.packages.default}/bin/schemesh";
            };

            devShells.default = pkgs.mkShell {
              buildInputs = sharedBuildInputs;
              nativeBuildInputs = sharedNativeBuildInputs;
            };
          };
        };
    }
```
