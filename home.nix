{ config
, pkgs
, pkgs-unstable
, lib
, osConfig
, ...
}:

{
  # Let Home Manager install and manage itself.
  programs.home-manager.enable = true;

  home.username = "app";
  home.homeDirectory = "/home/app";
  home.stateVersion = "25.05"; # Please read the comment before changing.

  # Env vars
  home.sessionVariables = {
    XDG_CONFIG_HOME = "${config.xdg.configHome}";
    XDG_CACHE_HOME = "${config.xdg.cacheHome}";
    XDG_DATA_HOME = "${config.xdg.dataHome}";
    XDG_STATE_HOME = "${config.xdg.stateHome}";
  };

  dconf.enable = true;

  #####################
  # NOTE: General programs and packages
  home.packages = (with pkgs; [
    # Utils
    tree # fs vis
    jq # CLI json explorer

    # Cloud
    openssl
  ]);


  #########################
  # General CLI tools

  # NOTE: Zsh setup
  # Manual setup: don't like how home-manager currently sets up zsh
  CUSTOM.programs.zsh.enable = true;
  programs.zoxide = {
    enable = true;
    enableZshIntegration = config.programs.zsh.enable;
  };
  programs.bat = {
    enable = true;
    extraPackages =
      let
        batPkgAttrs = lib.filterAttrs (key: val: lib.isType "package" val) pkgs.bat-extras;
        batPkgs = lib.mapAttrsToList (key: val: val) batPkgAttrs;
      in
      batPkgs;
  };
  programs.fzf = {
    enable = true;
    enableZshIntegration = config.programs.zsh.enable;
    colors = {
      "fg" = "#d0d0d0";
      "fg+" = "#d0d0d0";
      "bg" = "-1";
      "bg+" = "#262626";

      "hl" = "#5f87af";
      "hl+" = "#5fd7ff";
      "info" = "#afaf87";
      "marker" = "#80c9b8";

      "prompt" = "#80c9b8";
      "spinner" = "#9fffd9";
      "pointer" = "#e27739";
      "header" = "#87afaf";

      "border" = "#374142";
      "preview-scrollbar" = "#000000";
      "label" = "#aeaeae";
      "query" = "#d9d9d9";
    };
    defaultOptions = [
      "--border='rounded'"
      "--border-label='~ (fuzzy)'"
      "--border-label-pos='1'"
      "--preview-window='border-rounded'"
      "--prompt='> '"
      "--marker='>'"
      "--pointer='◆'"
      "--separator='─'"
      "--scrollbar='│'"
      "--info='right'"
      "--height '40%'"
    ];
  };
  programs.eza = {
    enable = true;
    enableZshIntegration = config.programs.zsh.enable;
    icons = "auto";
    colors = "always";
    extraOptions =
      [
        "--group-directories-first"
        "--header"
      ];
  };

}
