{ config
, pkgs
, ...
}:
{
  disko.imageBuilder = {
    enableBinfmt = true;
    pkgs = pkgs.buildPackages;
    kernelPackages = pkgs.buildPackages.linuxPackages_6_12_hardened;
    imageFormat = "qcow2";
  };

  fileSystems."/" = pkgs.lib.mkForce {
    fsType = "tmpfs";
  };
  fileSystems."/boot" = pkgs.lib.mkForce {
    device = pkgs.lib.mkForce "/dev/disk/by-partlabel/disk-main-ESP";
  };

  disko.devices = {
    nodev."/" = {
      fsType = "tmpfs";
      mountOptions = [
        "size=512M"
        "defaults"
        "mode=755"
      ];
    };
    disk = {
      main = {
        # When using disko-install, we will overwrite this value from the commandline
        device = "/dev/disk/by-partlabel/disk-main-nixos";
        type = "disk";
        imageSize = "5G";
        content = {
          type = "gpt";
          partitions = {
            MBR = {
              priority = 1; # Needs to be first partition
              start = "0";
              size = "1M";
              type = "EF02"; # for grub MBR
            };
            ESP = {
              priority = 2;
              type = "EF00";
              size = "63M";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [ "umask=0077" ];
              };
            };
            persist = {
              priority = 3;
              size = "1G";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/persist";
                mountOptions = [ "defaults" ];
              };
            };
            nix = {
              priority = 4;
              size = "100%";
              content = {
                type = "filesystem";
                format = "ext4";
                mountpoint = "/nix";
                mountOptions = [ "defaults" ];
              };
            };
          };
        };
      };
    };
  };

  fileSystems."/persist".neededForBoot = true;
  virtualisation.vmVariantWithDisko.virtualisation.fileSystems."/persist".neededForBoot = true;

  environment.persistence."/persist" = {
    directories = [
      "/etc/nixos"
      "/home"
      "/var/lib"
      "/var/log"
    ];

    files = [
      "/etc/machine-id"
      "/etc/ssh/ssh_host_rsa_key"
      "/etc/ssh/ssh_host_rsa_key.pub"
      "/etc/ssh/ssh_host_ed25519_key"
      "/etc/ssh/ssh_host_ed25519_key.pub"
    ];
  };
}
