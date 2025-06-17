{
  inputs = {
    #############################
    # NixOS-related inputs
    nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-25.05";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    flake-registry = {
      url = "github:nixos/flake-registry";
      flake = false;
    };

    #############################
    # Nix package management
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs-stable";
    };

    impermanence.url = "github:nix-community/impermanence";
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
      # wipe fs each boot
    , impermanence
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
          ;
      };

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


      ipcacheModules = [
        impermanence.nixosModules.impermanence
        determinate.nixosModules.default
        noChannelModule
        ./configuration.nix
        home-manager.nixosModules.default
        ({ config
         , lib ? home-manager.lib
         , ...
         }:
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.app = ./home.nix;
          })
      ];

    in
    {
      nixosConfigurations.ipcache = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        modules = ipcacheModules ++ [
        ];
      };

      nixosConfigurations.ipcache-vm = nixpkgs.lib.nixosSystem {
        system = "aarch64-linux";
        specialArgs = extraSpecialArgs;
        modules =
          # The key: reuse ALL modules from the original `ipcache` config...
          ipcacheModules
          ++ [
            # ...and add two more modules.

            # A. The module that enables building a QEMU VM runner script.
            "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"

            # B. An inline module to specify hardware resources.
            ({ ... }: {
              # Define the QEMU hardware settings. These are used by qemu-vm.nix
              # to generate the correct runner script.
              virtualisation.cores = 8;
              virtualisation.memorySize = 16 * 1024; # 16 GB in MB

              virtualisation.forwardPorts = [
                { host.port = 10022; guest.port = 22; } # Forward host port 2222 to guest port 22 for SSH
              ];

              # It's good practice to ensure it uses UEFI boot for aarch64
              virtualisation.useEFIBoot = true;
            })
          ];
      };

      # ===================================================================
      # 3. Flake outputs for building and running the VM.
      #    The platform here is your HOST's platform (e.g., x86_64-linux).
      # ===================================================================
      packages."x86_64-linux".ipcache-vm-runner =
        self.nixosConfigurations.ipcache-vm.config.system.build.vm;
    };
}

