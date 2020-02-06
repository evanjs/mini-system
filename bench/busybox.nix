{ pkgs, lib, config, ... }:
{
  config.nixpkgs.config.packageOverrides = pkgs: {
    busybox = pkgs.pkgsStatic.busybox.override { extraConfig = lib.readFile ./fixed.config; };
  };
}


