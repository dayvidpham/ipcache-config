inputs@{ nixpkgs
, nixpkgs-unstable
, nixpkgs-stable
, flake-registry
, ...
}:
({ config
 , inputs
 , ...
 }:
let
  inherit (inputs)
    nixpkgs
    nixpkgs-unstable
    nixpkgs-stable
    flake-registry
    ;
in
{
  nix.settings.experimental-features = [
    "nix-command"
    "ca-derivations"
    "dynamic-derivations"
    "flakes"
    "fetch-closure"
    "pipe-operators"
  ];
  nix.channel.enable = false;

  nix.registry.nixpkgs.flake = nixpkgs;
  nix.registry.nixpkgs-unstable.flake = nixpkgs-unstable;
  nix.registry.nixpkgs-stable.flake = nixpkgs-stable;

  environment.etc."nix/inputs/nixpkgs".source = "${nixpkgs}";
  environment.etc."nix/inputs/nixpkgs-unstable".source = "${nixpkgs-unstable}";
  environment.etc."nix/inputs/nixpkgs-stable".source = "${nixpkgs-stable}";

  nix.nixPath = [
    "nixpkgs=/etc/nix/inputs/nixpkgs"
    "nixpkgs-unstable=/etc/nix/inputs/nixpkgs-unstable"
    "nixpkgs-stable=/etc/nix/inputs/nixpkgs-stable"
  ];
  nix.settings.nix-path = [
    "nixpkgs=/etc/nix/inputs/nixpkgs"
    "nixpkgs-unstable=/etc/nix/inputs/nixpkgs-unstable"
    "nixpkgs-stable=/etc/nix/inputs/nixpkgs-stable"
  ];

  nix.settings.flake-registry = "${flake-registry}/flake-registry.json";
})

