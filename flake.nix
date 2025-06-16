{
  inputs = {
    #############################
    # NixOS-related inputs
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";

    nixpkgs-wsl.url = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-wsl.url = "github:nix-community/NixOS-WSL/main";

    flake-registry = {
      url = "github:nixos/flake-registry";
      flake = false;
    };

    #############################
    # Nix package management
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    home-manager = {
      url = "github:nix-community/home-manager/master";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    home-manager-wsl = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs-wsl";
    };

    #############################
    # Community tools
    nil-lsp = {
      url = "github:oxalica/nil";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };
  };

  outputs = inputs@{ 
    self
    , nixpkgs
    , nixpkgs-unstable
    , nixpkgs-stable
    , flake-registry
    # Package management
    , determinate
    , home-manager
    , nil-lsp
    , ... 
   }: let
    # NOTE: 'nixos' is the default hostname
    system = "aarch64-linux";
    nixpkgs-options = {
      inherit system;
      hostPlatform = system;

      config = {
        allowUnfree = true;
      };
    };

    pkgs = import nixpkgs nixpkgs-options;
    pkgs-unstable = import nixpkgs-unstable nixpkgs-options;
    pkgs-stable = import nixpkgs-stable nixpkgs-options;

    lib = pkgs.lib;

    # NOTE: Needs to be defined here to have access to nixpkgs and home-manager inputs
    noChannelModule = {
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
      nix.registry.home-manager.flake = home-manager;
      nix.registry.nixpkgs-unstable.flake = nixpkgs-unstable;
      nix.registry.nixpkgs-stable.flake = nixpkgs-stable;
      environment.etc."nix/inputs/nixpkgs".source = "${nixpkgs}";
      environment.etc."nix/inputs/nixpkgs-unstable".source = "${nixpkgs-unstable}";
      environment.etc."nix/inputs/nixpkgs-stable".source = "${nixpkgs-stable}";
      environment.etc."nix/inputs/home-manager".source = "${home-manager}";

      nix.nixPath = lib.mkForce [
        "nixpkgs=/etc/nix/inputs/nixpkgs"
        "nixpkgs-unstable=/etc/nix/inputs/nixpkgs-unstable"
        "nixpkgs-stable=/etc/nix/inputs/nixpkgs-stable"
        "home-manager=/etc/nix/inputs/home-manager"
      ];
      nix.settings.nix-path = lib.mkForce [
        "nixpkgs=/etc/nix/inputs/nixpkgs"
        "nixpkgs-unstable=/etc/nix/inputs/nixpkgs-unstable"
        "nixpkgs-stable=/etc/nix/inputs/nixpkgs-stable"
        "home-manager=/etc/nix/inputs/home-manager"
      ];

      nix.settings.flake-registry = "${flake-registry}/flake-registry.json";
    };

    in {
    nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
      modules = [
	determinate.nixosModules.default
        ./configuration.nix
        noChannelModule
      ];
    };
  };
}

