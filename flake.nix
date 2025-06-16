{
  inputs = rec {
    #############################
    # NixOS-related inputs
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs.url = nixpkgs-stable.url;

    flake-registry = {
      url = "github:nixos/flake-registry";
      flake = false;
    };

    #############################
    # Nix package management
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    home-manager = {
      url = "github:nix-community/home-manager/25.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    #############################
    # Community tools
    nil-lsp = {
      url = "github:oxalica/nil";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    dayvidpham = {
      url = "github:dayvidpham/dotfiles";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-stable.follows = "nixpkgs-stable";
      inputs.nixpkgs-unstable.follows = "nixpkgs-unstable";
      inputs.determinate.follows = "determinate";
      inputs.home-manager.follows = "home-manager";
      inputs.nil-lsp.follows = "nil-lsp";
    };
  };

  outputs =
    inputs@{ self
    , nixpkgs
    , nixpkgs-unstable
    , nixpkgs-stable
    , flake-registry
      # Package management
    , determinate
    , home-manager
    , nil-lsp
      # My own config
    , dayvidpham
    , ...
    }:
    let
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

      # NOTE: Common args to be passed to nixosConfigs and homeConfigurations
      specialArgs = {
        inherit
          pkgs-unstable
          pkgs-stable
          ;
      };

      extraSpecialArgs = {
        inherit
          pkgs-unstable
          pkgs-stable
          nil-lsp
          ;
      };

      # NOTE: Needs to be defined here to have access to nixpkgs and home-manager inputs
      noChannelModule = (
        { nixpkgs
        , nixpkgs-stable
        , nixpkgs-unstable
        , home-manager
        , flake-registry
        , ...
        }:
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
        }
      );

    in
    {
      nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          determinate.nixosModules.default
          noChannelModule
          dayvidpham.nixosModules.system
          ./configuration.nix
          home-manager.nixosModules.default
          {
            modules = [
              dayvidpham.nixosModules.home-manager
            ];
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.app = ./home.nix;
          }
        ];
      };
    };
}

