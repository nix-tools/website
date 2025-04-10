+++
date = '2025-04-10T14:35:43Z'
draft = false
title = 'Rust Toolchains using Nix'
+++

There are many ways to Rust using Nix. This article:

- Reviews existing articles on setting up Rust toolchains
- Describes several of the approaches ordered by popularity, maturity and benefits.

## References

- [Documentation for Rust language frameworks][nixpkgs-rust] in nixpkgs
- [Development Environment for Rust][nixlang-wiki-rust] on the nixlang wiki
- [Nix shell with rustup][ayats-org-rust] on the ayats.org blog

[nixpkgs-rust]: https://github.com/NixOS/nixpkgs/blob/master/doc/languages-frameworks/rust.section.md
[nixlang-wiki-rust]: https://github.com/nixlang-wiki/nixlang-wiki/blob/main/nix/how-to/development-environment-for-rust.md
[ayats-org-rust]: https://ayats.org/blog/nix-rustup

## Just `rustup`

The simplest way to get started is just adding `rustup` to your system configuration:

```nix
{ pkgs, ... }: {
  environment.systemPackages = [
    pkgs.rustup
  ];
}
```
