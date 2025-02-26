{
  description = "nix.tools website";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = {nixpkgs, ...}: let
    system = "x86_64-linux";
    pkgs = nixpkgs.legacyPackages.${system};
    #hugo-theme = builtins.fetchTarball {
    #  name = "hugo-book-theme";
    #  url = "https://github.com/alex-shpak/hugo-book/archive/645c868cec1396548456eac68205eabbd8ca9564.tar.gz";
    #  sha256 = "12gl336yj2cisxnmaniaxm4ayq02g3skvp7pk5686m5nm4wlrz2q";
    #};
  in {
    devShells.${system}.default = pkgs.mkShellNoCC {
      packages = [
        pkgs.hugo
        pkgs.just
      ];

      #shellHook = ''
      #  mkdir -p themes
      #  ln -snf "${hugo-theme}" themes/default
      #'';
    };
  };
}
