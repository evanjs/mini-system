{ pkgs, lib, config, ... }:
let
  sources = import ./nix/sources.nix;
in rec {
  imports = [
    (sources.nixpkgs + "/nixos/modules/profiles/minimal.nix")
  ];
  fileSystems = {
    "/" = {
      device = "/dev/sda1";
      fsType = "ext4";
      noCheck = true;
    };
  };

  boot = {
    loader = {
      grub = {
        enable = false;
      };
    };
    kernelPackages = pkgs.mylinuxPackages_4_19;

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

  environment.systemPackages = with pkgs;
  [
    (callPackage "/home/evanjs/src/rjg/copilot/realtime" { deploy = false; })
  ];
  fonts.fontconfig.enable = false;
  security.polkit.enable = false;
  #services.udisks2.enable = lib.mkForce false;
}
