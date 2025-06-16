{ config
, pkgs
, pkgs-unstable
, lib ? config.lib
, modulesPath
, ...
}:

{
  # To build the configuration or use nix-env, you need to run
  # either nixos-rebuild --upgrade or nix-channel --update
  # to fetch the nixos channel.

  # This configures everything but bootstrap services,
  # which only need to be run once and have already finished
  # if you are able to see this comment.
  imports = [
    ./hardware-configuration.nix
  ];

  system.stateVersion = "25.05";
  boot.kernelPackages = pkgs.linuxPackages_6_12;
  time.timeZone = "America/Vancouver";

  ####################################
  # 'app' user setup

  users.groups.app.name = "app";
  users.groups.app.gid = 1000;

  users.users.app.enable = true;
  users.users.app.name = "app";
  users.users.app.group = "users";
  users.users.app.extraGroups = [
    "app"
    "ipcache"
    "wireguard"
    "vpn"
    "wheel"
  ];
  users.users.app.isNormalUser = true;
  users.users.app.uid = 1000;
  users.users.app.linger = true;
  users.users.app.autoSubUidGidRange = true;

  ####################################
  # ssh setup

  services.fail2ban.enable = true;
  services.fail2ban.bantime-increment.enable = true;

  services.openssh.enable = true;
  services.openssh.sftpFlags = [
    "-f AUTHPRIV"
    "-l INFO"
  ];
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.KbdInteractiveAuthentication = false;
  services.openssh.settings.AuthenticationMethods = "publickey";
  services.openssh.settings.X11Forwarding = true;

  services.openssh.authorizedKeysInHomedir = true;
  services.openssh.authorizedKeysFiles = [
    "%h/.ssh/authorized_keys"
    "/etc/ssh/authorized_keys.d/%u"
  ];

  services.openssh.settings.PermitRootLogin = "no";
  services.openssh.settings.DenyUsers = [ "root" ];
  services.openssh.settings.DenyGroups = [ "root" ];

  services.openssh.settings.Ciphers = [
    "chacha20-poly1305@openssh.com"
    "aes256-gcm@openssh.com"
    "aes128-gcm@openssh.com"
  ];

  # Allow these pubkeys to ssh into 'app' user
  users.users.app.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPbEq1/i8sCEuKZV5xFr+S5T12u54kEyqYHqD2/Xu2kX minttea@desktop"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDIY92qsMiI4BLtinVSJgS7fkhMKdZefRc72LYB8HddQkCuMADp/dovHPY9DJc23mmSJxeew/NCFasc5CmywCNRmfQYaCvxiblAQiEbGFrmoW1gGn0idXW+YRjJasFnR4iwADb10kR71m4QMwqOSdrrubnYfWZy/+a03/VOMQFSMANZAETAuTnoZRRcCPO5VdrowHr9vOy7+NY1WktiTrttjHrmCh1S/JUWB61D2sYHjrqNk6FBad2SVg6uICjJVLy0VQsJeYCoXA9Gw/Bi7BCctamubHwjQBOz7QZN8829d6OsYRkXEtHfJxEgHQ8JeS9JXX+kiAunbmHMaUJKgfLLN78rYzRYDD46F2uKAi8EOovGuQH2x+/CgOZFvQ3US4zqVCXgnoWmGgjGZgZwYFp0YTHLMG7wRTOHIJjoiYKp1BWQYGEINMFKBduNAuPCm9PyuUOQssAVqBoUxPwYUEcTgdL0XpNjchG8gKEwvnZnOWxm8FdUl64GElsAA/DzsrFJNYcwya+wiYT/WKc4rCGEziI2N7/5dNNnSDdp9NeVjbTS0PHtdbqG0U2FsZ1FP6EvGngJWDm5D/Y0nPwBBKIXMIKVZ10eZ+Z50kHx7O35bFOaYBNVESHFqcpzYNdFEGVqm2fKeZcTx5GD3AavZIcxHV4SjTuL6sWURdnbnfe5Vw=="
  ];
}
