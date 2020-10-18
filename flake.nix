{
  description = "A feature flags client for elixir";
  inputs.nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
  inputs.flake-utils.url = "github:numtide/flake-utils";

  outputs = { self, nixpkgs, flake-utils }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        erlangR23 = pkgs.beam.packages.erlangR23;
        erlang = erlangR23.erlang;
        elixir = erlangR23.elixir_1_10;
      in {
        devShell = pkgs.mkShell {
          buildInputs = [ elixir ];
          ERL_INCLUDE_PATH = "${erlang}/lib/erlang/usr/include";
        };
      });
}
