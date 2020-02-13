{ pkgs, lib, config, ... }:
with lib;
let
  rjg-overlay = (import /home/evanjs/src/rjg/nixos/overlay/overlay.nix );
  sources = import ./nix/sources.nix;
  #pkgs = (import sources.nixpkgs { overlays = [ rjg-overlay ]; });
  pkgs = (import /home/evanjs/src/nixpkgs { overlays = [ rjg-overlay]; });
  linuxPackages_4_1 = pkgs.callPackage ./linux_4_1.nix {};

in rec {
  imports = [
    #(sources.nixpkgs + "/nixos/modules/profiles/minimal.nix")
    <nixpkgs/nixos/modules/profiles/minimal.nix>
  ];
  fileSystems = {
    "/" = {
      device = "nodev";
    };
  };

  boot = {
    loader = { grub = { enable = false; }; };
    kernelPackages = pkgs.linuxPackagesFor linuxPackages_4_1;
    initrd = {
      network = {
        enable = true;
        ssh = {
          enable = true;
          authorizedKeys = [
            "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDdtmpVNazxU/hWptbq/zr8dNKy7BJGcLntbyoRjzq0v2HwY0LSZjTKkldyWShEwRtJrRrqf1JK2FSF1IQ5IJ/q/YyjdsJ3JGJN+/oNTaBQr1bGRuDs9yS9kalvaRpRHwH/56Kfv9rLfhGPea/sTQPS4eG/0Oo3uVz/8ZxeP1JHIHGD43gY0lmFTQEnCgdGQdTRRdgXaAQholAjP+5GbdyJhU4zH1ld2dS3jFSU8uuUJVViVO9ElNZPV8k0bDudeC8qrY7AvsmMvybh3fsJha8U5e1y4ocB8PO78YMs+KEUGuHJp3UIj09KhYLx/zruTOGjBJVWtDtbIezIcr7KpZhj evanjs@nixjgtoo"
          ];
        };
      };
    };
  };


  hardware.enableRedistributableFirmware = true;

  fonts.fontconfig.enable = false;
  security.polkit.enable = false;
  services.udisks2.enable = lib.mkForce false;
}
