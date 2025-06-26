{ config
, pkgs
, pkgs-unstable
, pkgs-stable
, lib ? config.lib
, modulesPath
, ...
}:
let
  domain = "vpn.gateway.minttea.oraclevcn.com";
  port = 22443;
in
{
  imports = [
    # oci-common includes qemu-guest
    "${modulesPath}/virtualisation/oci-common.nix"
    "${modulesPath}/profiles/hardened.nix"
  ];

  ####################################
  # Headscale config

  services.headscale = {
    enable = true;
    address = "localhost";
    inherit port;

    settings = {
      server_url = "https://${domain}:22443";
      dns = {
        override_local_dns = true;
        base_domain = "tailscale.${domain}";
        magic_dns = true;
        #domains = [
        #  "tailscale.${domain}"
        #];
        nameservers.global = [
          # AdGuard
          "2a10:50c0::ad1:ff"
          "94.140.14.14"
          # Quad9
          "2620:fe::fe"
          "9.9.9.9"
        ];
        search_domains = [
          "vpn.minttea"
          "tailscale.${domain}"
        ];
      };
    };
  };

  services.caddy = {
    enable = true;
    email = "davidpham.tech@gmail.com";
    globalConfig = ''
      servers {
        protocols h3
        trusted_proxies static private_ranges
        listener_wrappers {
          http_redirect
          tls
        }
      }
    '';
    virtualHosts = {
      "${domain}" = {
        listenAddresses = [
          "127.0.0.1"
          "::1"
        ];
        serverAliases = [
          "www.${domain}"
        ];
        extraConfig = ''
          reverse_proxy {
            to https://localhost:22443 https://[::1]:22443
          }
        '';
      };
    };
  };



  ####################################
  # VM options

  oci.efi = true;
  services.cloud-init.enable = true;
  services.cloud-init.network.enable = true;


  ####################################
  # General system

  system.stateVersion = "25.05";
  boot.kernelPackages = pkgs.linuxPackages_6_12_hardened;


  ####################################
  # Many options inspired by Xe Iaso
  # https://archive.is/ZzBkF

  security.polkit.enable = true;
  nix.settings.allowed-users = [ "root" ];
  security.sudo.execWheelOnly = true;
  security.allowSimultaneousMultithreading = true; # set to false by hardened, whatever

  security.auditd.enable = true;
  security.audit.enable = true;
  security.audit.rules = [
    "-a exit,always -F arch=b64 -S execve"
  ];



  # Only allow executables from /nix/store
  fileSystems."/".options = [ "noexec" ];
  fileSystems."/boot".options = [ "noexec" ];
  #fileSystems."/etc/nixos".options = [ "noexec" ];
  #fileSystems."/home".options = [ "noexec" ];
  #fileSystems."/var/lib".options = [ "noexec" ];
  #fileSystems."/var/log".options = [ "noexec" ];


  ####################################
  # systemd-networkd setup

  networking.hostName = "vpn";
  networking.useNetworkd = true;
  networking.useDHCP = true;
  networking.firewall.enable = true;
  networking.usePredictableInterfaceNames = lib.mkForce true;

  systemd.network.enable = true;
  systemd.network.wait-online.enable = true;

  systemd.network.networks."50-enp0s6" = {
    matchConfig.Name = "enp0s6";
    networkConfig = {
      DHCP = "yes";
      IPv6AcceptRA = true;
      Description = "paravirtualized network interface";
    };
    dhcpV4Config = {
      UseDNS = true;
    };
    dhcpV6Config = {
      UseDNS = true;
    };
    ipv6AcceptRAConfig = {
      UseDNS = true;
    };
    linkConfig.RequiredForOnline = "routable";
  };

  ####################################
  # 'app' user setup

  users.groups."ssh-users".name = "ssh-users";
  users.groups."ssh-users".gid = 2022;
  users.groups."ssh-users".members = [ "app" ];

  users.users.app.enable = true;
  users.users.app.uid = 1000;
  users.users.app.name = "app";
  users.users.app.extraGroups = [
    "ipcache"
    "wireguard"
    "vpn"
    # ^-- some extra groups that might be useful
    "ssh-users" # only ssh-users can be ssh'd into
    "wheel"
  ];
  users.users.app.isNormalUser = true;
  users.users.app.linger = true;
  users.users.app.autoSubUidGidRange = true;

  # Generate this using mkpasswd -m sha-512
  users.users.app.hashedPassword = "$6$ZiinSsasDEx3k.Q4$0yBZV5IclkhQXfUp1qjE816075fHIU2mMqS9rf68EcUAWVbShdxP5CeAZbfqHBzxNZiKwwjmTtrmEf86e1z0G/";

  # Allow these pubkeys to ssh into 'app' user
  users.users.app.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFE9Bzi5oGzx9d68d4lVLgo/d1GypUwE7MhAQ7Z32LlR minttea@flowX13"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPbEq1/i8sCEuKZV5xFr+S5T12u54kEyqYHqD2/Xu2kX minttea@desktop"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJDiMx4rHgmNc/fwHcffw8pRT2xfsUtfgnUKjKxRIWeG minttea@desktop-wsl"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE8yJl68/OAqCDrvGRVJlTNC3OwByzt5MIaAQI+Es3Ir minttea@flowX13-wsl"
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDIY92qsMiI4BLtinVSJgS7fkhMKdZefRc72LYB8HddQkCuMADp/dovHPY9DJc23mmSJxeew/NCFasc5CmywCNRmfQYaCvxiblAQiEbGFrmoW1gGn0idXW+YRjJasFnR4iwADb10kR71m4QMwqOSdrrubnYfWZy/+a03/VOMQFSMANZAETAuTnoZRRcCPO5VdrowHr9vOy7+NY1WktiTrttjHrmCh1S/JUWB61D2sYHjrqNk6FBad2SVg6uICjJVLy0VQsJeYCoXA9Gw/Bi7BCctamubHwjQBOz7QZN8829d6OsYRkXEtHfJxEgHQ8JeS9JXX+kiAunbmHMaUJKgfLLN78rYzRYDD46F2uKAi8EOovGuQH2x+/CgOZFvQ3US4zqVCXgnoWmGgjGZgZwYFp0YTHLMG7wRTOHIJjoiYKp1BWQYGEINMFKBduNAuPCm9PyuUOQssAVqBoUxPwYUEcTgdL0XpNjchG8gKEwvnZnOWxm8FdUl64GElsAA/DzsrFJNYcwya+wiYT/WKc4rCGEziI2N7/5dNNnSDdp9NeVjbTS0PHtdbqG0U2FsZ1FP6EvGngJWDm5D/Y0nPwBBKIXMIKVZ10eZ+Z50kHx7O35bFOaYBNVESHFqcpzYNdFEGVqm2fKeZcTx5GD3AavZIcxHV4SjTuL6sWURdnbnfe5Vw=="
  ];

  ####################################
  # ssh setup

  services.fail2ban.enable = true;
  services.fail2ban.bantime-increment.enable = true;

  services.openssh.enable = true;
  services.openssh.sftpFlags = [
    "-f AUTHPRIV"
    "-l INFO"
  ];

  # pubkey auth only, no ssh into root
  services.openssh.settings.PasswordAuthentication = false;
  services.openssh.settings.KbdInteractiveAuthentication = false;
  services.openssh.settings.AuthenticationMethods = "publickey";
  services.openssh.settings.PermitRootLogin = "no";
  services.openssh.settings.DenyUsers = [ "root" ];
  services.openssh.settings.DenyGroups = [ "root" ];
  services.openssh.settings.AllowGroups = [ "ssh-users" ];
  services.openssh.settings.AllowTcpForwarding = true;

  services.openssh.settings.X11Forwarding = false;
  services.openssh.settings.AllowStreamLocalForwarding = false;
  services.openssh.settings.AllowAgentForwarding = false;
  services.openssh.ports = [ 22 ];
  services.openssh.openFirewall = true;

  services.openssh.authorizedKeysInHomedir = true;
  services.openssh.authorizedKeysFiles = [
    "%h/.ssh/authorized_keys"
    "/etc/ssh/authorized_keys.d/%u"
  ];

  services.openssh.settings.Ciphers = [
    "chacha20-poly1305@openssh.com"
    "aes256-gcm@openssh.com"
    "aes128-gcm@openssh.com"
  ];
}
