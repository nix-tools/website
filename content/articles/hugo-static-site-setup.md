---
title: "Setting up a Hugo static website with Nix"
date: 2025-02-24
draft: false
---

## tl;dr

See the tutorial code at https://github.com/nix-tools/nix-hugo

This tutorial…

- Provides a development environment for running interactively
- Provides a derivation for deployment on NixOS
- Deploys to a webserver using `just`, `ssh` and `scp`

## Step 0: Prerequisites

- You have Nix installed (required)
- You have flakes enabled (required)
- You have nix-direnv enabled (recommended)

## Step 1: A development environment

A dev shell is provided in two ways: as a shell.nix and as a flake.nix, pick one.

### shell.nix

A shell.nix is sufficient for providing a dev shell.

```nix
let
  nixpkgs = builtins.fetchTarball
    "https://github.com/nixos/nixpkgs/archive/nixos-unstable.tar.gz";
  pkgs = import nixpkgs {};
in
  pkgs.makeShellNoCC {
    packages = [
      pkgs.hugo
      pkgs.just
    ];
  }
```

### flake.nix

A flake has other options for deploying the static website later.

```nix
{
  description = "Hugo Website";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux";
    pkgs = nixpkgs { inherit system; };
  in {
    devShells.${system}.default = pkgs.mkShellNoCC {
      packages = [
        pkgs.hugo
        pkgs.just
      ];
    };
  };
}
```

Some deliberate limitations:

- Only an environment for `x86_64-linux` is provided
- You can change this to `aarch64-darwin` for MacOS
- Only `hugo` and `just` are added to the environment

At this point, the flake only exports a single devShells entry:

```sh
$ nix flake show
git+file:///home/sshine/Projects/website
└───devShells
    └───x86_64-linux
        └───default: development environment 'nix-shell'
```

You can enter the development environment by typing `nix develop`.

Enabling direnv with flakes makes the dev environment available as an overlay in your existing shell:

```sh
$ echo 'use flake' > .envrc
$ direnv allow
$ hugo version
hugo v0.143.1+extended+withdeploy linux/amd64 BuildDate=unknown VendorInfo=nixpkgs
```

You can also enable direnv for a shell.nix by `echo 'use nix' > .envrc` instead.

This installs the Hugo CLI, but there is no website yet.

## Step 2: Bootstrap Hugo

The main purpose of the development environment is to add website content.

But it will also work for bootstrapping the website and modifying its appearance.

[hugo-quick]: https://gohugo.io/getting-started/quick-start/

To initialize the Hugo scaffolding, type:

```sh
$ hugo new site . --force
```

The `--force` parameter allows writing to a non-empty directory.

This creates a hugo.toml that, when modified minimally, may look like:

```toml
baseURL = 'https://nix.tools/'
languageCode = 'en-us'
title = 'nix.tools'
```

A lot of subsequent hugo.toml settings are theme-sensitive.

Commit these files to git for now.

## Step 3: Adding a theme

We look among [Hugo themes][hugo-themes] and settle for [hugo-theme-m10c][hugo-theme-m10c].

[hugo-themes]: https://themes.gohugo.io/
[hugo-theme-m10c]: https://github.com/vaga/hugo-theme-m10c

Instead of git cloning or downloading the theme and adding it to this repository, we create a [derivation][nix-derivation] in flake.nix:

[nix-derivation]: https://nix.dev/manual/nix/2.17/language/derivations

```nix
{
  description = "Hugo Website";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    hugo-theme = builtins.fetchTarball {
      name = "hugo-theme-m10c";
      url = "https://github.com/vaga/hugo-theme-m10c/archive/8295ee808a8166a7302b781895f018d9cba20157.tar.gz";
      sha256 = "12jvbikznzqjj9vjd1hiisb5lhw4hra6f0gkq1q84s0yq7axjgaw";
    };
  in {
    devShells.${system}.default = pkgs.mkShellNoCC {
      packages = [
        pkgs.hugo
        pkgs.just
      ];

      shellHook = ''
        mkdir -p themes
        ln -snf "${hugo-theme}" themes/default
      '';
    };
  };
}
```

Here, `hugo-theme` is bound to the derivation made by `builtins.fetchTarball {...}`.

When a derivation is rendered as a string, it becomes the directory path in which the derivation lives.

There is a trick to figuring out the `sha256` value: Leave it empty, like so: 

```nix
hugo-theme = builtins.fetchTarball {
  name = "hugo-theme-m10c";
  url = "https://github.com/vaga/hugo-theme-m10c/archive/8295ee808a8166a7302b781895f018d9cba20157.tar.gz";
  sha256 = ""; # leave this empty
};
```

and watch the derivation fail:

```
error: hash mismatch in file downloaded from 'https://github.com/vaga/hugo-theme-m10c/archive/8295ee808a8166a7302b781895f018d9cba20157.tar.gz':
         specified: sha256:0000000000000000000000000000000000000000000000000000
         got:       sha256:12jvbikznzqjj9vjd1hiisb5lhw4hra6f0gkq1q84s0yq7axjgaw
```

and then copy the sha256 back into the file.

The `shellHook` symlinks `hugo-theme` into `themes/default` so a theme can be chosen in hugo.toml:

```toml
baseURL = 'https://nix.tools/'
languageCode = 'en-us'
title = 'nix.tools'
theme = 'default'
```

The theme is never added to version control. It is cached and symlinked from the Nix store. The main advantage is that we don't need to deal more with the theme, it's there. The disadvantage is that modifying the theme is difficult. This does not address vendoring the theme to prevent build failure in case the theme repository is deleted on GitHub. It also does not address extending the theme locally.

At this point there are two commands that are good to know for creating content:

```sh
$ hugo serve -D  # aka --buildDrafts
$ hugo new content content/posts/hello-world.md
```

I like to collect commands in an executable cheatsheet called [`justfile`][just]:

[just]: https://github.com/casey/just

```justfile
# See available `just` subcommands
list:
    just --list

# Create scaffolding and hugo.toml
init:
    hugo new site . --force

# Serve website on http://127.0.0.1:1313/
serve:
    hugo serve -D

# Create new post in content/posts/
post MDFILE:
    mkdir -p content/posts
    hugo new content 'content/posts/{{ MDFILE }}' || true
```

This way, when I get back to my project after months or years of inactivity, having completely forgotten the particular subcommands, the justfile reminds me of the most relevant commands I might type in this project. If some action requires several commands in the correct order, the justfile will remember the order and any relationship between the parameters.

## Step 4: Simplified deployment via SSH/SCP

Deployment with Nix gets a little complicated, so let’s just rehash how one might do it without:

```sh
# Generate static assets in public/
$ hugo

# Compress and upload static assets
$ tar cfz public.tgz public/
$ scp public.tgz server:/var/www/website
$ ssh server 'cd /var/www/website && tar xfz public.tgz'
```

This can be summarized as a justfile action:

```justfile
# Deploy to DIR on SERVER using tar/ssh/scp
deploy SERVER='nix.tools' DIR='/var/www/nix.tools':
    hugo
    tar cfz public.tgz public/
    scp public.tgz {{ SERVER }}:{{ DIR }}
    ssh {{ SERVER }} 'cd {{ DIR }} && tar xfz public.tgz'
```

and running e.g. `just deploy` or `just deploy nix.tools /var/www/nix.tools`.

Deploying a static website like this is enough for a lot of people, but a later article will expand on deploying with flakes.

## Step 5: Setting up a website with Nginx and Let’s Encrypt

Assuming your webserver runs NixOS, here is a configuration for setting up a domain on nginx with Let's Encrypt TLS.

(If your webserver doesn't run NixOS, it easily could using [nixos-anywhere][nixos-anywhere].)

[nixos-anywhere]: https://github.com/nix-community/nixos-anywhere

A small gotcha: You have to deploy the website once without TLS:

Let's Encrypt's `certbot` will deploy a challenge to the unencrypted website, which requires the unencrypted website to be around for that to happen.

```nix
{ ... }:
{
  security.acme = {
    acceptTerms = true;
    defaults.email = "john.doe@example.org";
  };

  services.nginx = {
    enable = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;
    recommendedProxySettings = true;
    recommendedTlsSettings = true;

    virtualHosts."nix.tools" = {
      # forceSSL = true;   # deploy without this first
      # enableACME = true; # deploy without this first
      root = "/var/www/nix.tools/public";
    };
  };
}
```

It makes sense to add this as part of your webserver's Nix configuration.

Finally, a `.gitignore` appropriate for this project:

```
# Hugo output
public/
public.tgz

# Misc.
.hugo_build.lock
.direnv/
```
