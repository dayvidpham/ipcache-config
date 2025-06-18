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
  };

  outputs =
    inputs@{ self
    , nixpkgs
    , nixpkgs-unstable
    , nixpkgs-stable
    , flake-registry
      # Package management
    , determinate
      # wipe fs each boot
    , impermanence
    , ...
    }:
    let
      disableChannels.nixosModules.default = import ./disable-channels.nix inputs;

      mkFlakeArgsNixosAlienSystem =
        { buildPlatform
        , hostPlatform
        , ...
        }: rec {
          nixpkgs-options = {
            # buildPlatform := the arch that produces build artifacts, may not actually boot the system
            # hostPlatform := the arch that will boot the system config
            # buildPlatform -> produces build artifacts -> system config booted by hostPlatform
            inherit buildPlatform hostPlatform;
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

          ipcacheModules = [
            impermanence.nixosModules.impermanence
            determinate.nixosModules.default
            disableChannels.nixosModules.default
            ./configuration.nix
            {
              nixpkgs.hostPlatform.system = hostPlatform;
            }
          ];
          vmModules = [
            # A. The module that enables building a QEMU VM runner script.
            "${nixpkgs}/nixos/modules/virtualisation/qemu-vm.nix"

            # B. An inline module to specify hardware resources.
            ({ config, ... }: {
              # Define the QEMU hardware settings. These are used by qemu-vm.nix
              # to generate the correct runner script.
              virtualisation.cores = 8;
              virtualisation.memorySize = 16 * 1024; # 16 GB in MB

              virtualisation.forwardPorts = [
                { host.port = 10022; guest.port = 22; } # Forward host port 10022 to guest port 22 for SSH
              ];

              # It's good practice to ensure it uses UEFI boot for aarch64
              virtualisation.useEFIBoot = true;

              # Ues this system's config as an image
              virtualisation.diskImage = config.build.system.images.oci;
            })
          ];
        };

      mkNixosAlienSystem = (
        { buildPlatform
        , hostPlatform
        , ...
        }:
        let
          alienSystemArgs = mkFlakeArgsNixosAlienSystem buildPlatform hostPlatform;
        in
        rec {
          nixosConfigurations.${buildPlatform}.vpn = {
            inherit (alienSystemArgs) buildPlatform hostPlatform specialArgs;
            modules = alienSystemArgs.ipcacheModules ++ [
            ];
          };

          nixosConfigurations.${buildPlatform}.vm = nixpkgs.lib.nixosSystem {
            inherit (alienSystemArgs) buildPlatform hostPlatform specialArgs;
            modules = alienSystemArgs.ipcacheModules
              ++ alienSystemArgs.vmModules
              ++ [
            ];
          };

          # ===================================================================
          # 3. Flake outputs for building and running the VM.
          # ===================================================================
          packages.${buildPlatform}.oci-image =
            nixosConfigurations.vm.config.system.build.images.oci;

          packages.${buildPlatform}.vm-runner =
            nixosConfigurations.vm.config.system.build.vm;

        }

      );


    in
    { }

