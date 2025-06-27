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
    # Nix itself
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";

    impermanence.url = "github:nix-community/impermanence";

    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs =
    inputs@{ self
    , nixpkgs
    , nixpkgs-unstable
    , nixpkgs-stable
    , flake-registry
      # Package management
    , determinate
      # utils
    , impermanence
    , disko
    , ...
    }:
    let
      disableChannels.nixosModules.default = import ./disable-channels.nix inputs;

      mkFlakeArgsNixosAlienSystem =
        buildPlatform:
        hostPlatform:
        rec {
          inherit buildPlatform hostPlatform;

          nixpkgs-options = {
            # buildPlatform := the arch that produces build artifacts, may not actually boot the system
            # hostPlatform := the arch that will boot the system config
            # buildPlatform -> produces build artifacts -> system config booted by hostPlatform

            config = {
              allowUnfree = true;
            };
          };

          pkgs = import nixpkgs nixpkgs-options;
          pkgs-unstable = import nixpkgs-unstable nixpkgs-options;
          pkgs-stable = import nixpkgs-stable nixpkgs-options;

          lib = pkgs.lib;

          specialArgs = {
            # NOTE: Common args to be passed to nixosConfigs
            inherit
              pkgs-unstable
              pkgs-stable
              ;
          };

          vmModules = [
            # A. The module that enables building a QEMU VM runner script.
            "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"

            # B. An inline module to specify hardware resources.
            ({ config, lib, options, ... }: {
              virtualisation = {
                cores = 4;
                memorySize = 16 * 1024; # 16 GB in MB
                forwardPorts = [
                  { host.port = 10022; guest.port = 22; } # Forward host port 10022 to guest port 22 for SSH
                  { host.port = 20022; guest.port = 22; } # Forward host port 10022 to guest port 22 for SSH
                ];
                #It's good practice to ensure it uses UEFI boot for aarch64
                useEFIBoot = true;


              } // lib.optionalAttrs (options.virtualisation ? vmVariantWithDisko) {
                vmVariantWithDisko = {
                  virtualisation = {
                    cores = 8;
                    memorySize = 16 * 1024; # 16 GB in MB
                    forwardPorts = [
                      { host.port = 10022; guest.port = 22; } # Forward host port 10022 to guest port 22 for SSH
                    ];
                    # It's good practice to ensure it uses UEFI boot for aarch64
                    useEFIBoot = true;
                  };
                };
              };

              # Define the QEMU hardware settings. These are used by qemu-vm.nix
              # to generate the correct runner script.

            })
          ];

          ipcacheModules = [
            {
              nixpkgs = {
                inherit buildPlatform hostPlatform;
              };
            }
            #impermanence.nixosModules.impermanence
            #disko.nixosModules.default
            determinate.nixosModules.default
            disableChannels.nixosModules.default
            ./configuration.nix
            #./disko.nix
          ];
        };

      mkAlienSystem = buildPlatform: hostPlatform: rec {
        nixosConfigurations = rec {
          hs0 =
            let
              alienSystemArgs = (mkFlakeArgsNixosAlienSystem buildPlatform buildPlatform);
            in
            nixpkgs.lib.nixosSystem {
              system = alienSystemArgs.hostPlatform;
              inherit (alienSystemArgs) specialArgs;
              modules = builtins.concatLists [
                alienSystemArgs.ipcacheModules
              ];
            };

          #######################################
          # cross-compilation currently broken
          # see https://github.com/NixOS/nixpkgs/issues/330308
          "hs0-${hostPlatform}" =
            let
              alienSystemArgs = mkFlakeArgsNixosAlienSystem buildPlatform systems.hostPlatform;
            in
            false && nixpkgs.lib.nixosSystem {
              system = alienSystemArgs.hostPlatform;
              inherit (alienSystemArgs) specialArgs;
              modules = builtins.concatLists [
                alienSystemArgs.ipcacheModules
              ];
            };

          hs0-vm = hs0.config.system.build.vm;

          # ===================================================================
          # 3. Flake outputs for building and running the VM.
          # ===================================================================
          #packages.${buildPlatform}."oci-image-${hostPlatform}" =
          #  nixosConfigurations.vm.config.system.build.images.oci;

        };

        oci-image = nixosConfigurations.hs0.config.system.build.images.oci;
        vm-runner = nixosConfigurations.hs0.config.system.build.vm;
      };

      # Basically, an enum
      systems.x86_64-linux = "x86_64-linux";
      systems.aarch64-linux = "aarch64-linux";
    in
    rec {
      packages.x86_64-linux = with systems; mkAlienSystem x86_64-linux aarch64-linux;
      nixosConfigurations.x86_64-linux = packages.x86_64-linux.nixosConfigurations;

      packages.aarch64-linux = with systems; mkAlienSystem aarch64-linux aarch64-linux;
      nixosConfigurations.aarch64-linux = packages.aarch64-linux.nixosConfigurations;
    };
}





