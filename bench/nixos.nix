{ pkgs, lib, config, ... }:
let
  sources = import ./nix/sources.nix;
  busybox = pkgs.pkgsStatic.busybox.override {
    extraConfig = lib.readFile ./fixed.config;
  };
  pkgs = (import sources.nixpkgs { }).extend overlay;
  lib = pkgs.lib;
  #x86_64 = pkgs.extend overlay;
  x86_64 = pkgs;
  overlay = self: super: {
    uart-manager = self.stdenv.mkDerivation {
      name = "uart-manager";
      src = ./uart-manager;
    };
    script = pkgs.writeTextFile {
      name = "init";
      text = ''
        #!${self.busybox}/bin/ash
        export PATH=/bin
        mknod /dev/kmsg c 1 11
        exec > /dev/kmsg 2>&1
        mount -t proc proc proc
        mount -t sysfs sys sys
        mount -t devtmpfs dev dev
        mount -t debugfs debugfs /sys/kernel/debug
        exec > /dev/ttyAMA0 2>&1 < /dev/ttyAMA0
        /bin/sh > /dev/ttyAMA0 < /dev/ttyAMA0
        echo sh failed
      '';
      executable = true;
    };
    myinit = self.stdenv.mkDerivation {
      name = "myinit";
      nativeBuildInputs = [ x86_64.nukeReferences ];
      buildCommand = ''
        $CC ${./my-init.c} -o $out
        nuke-refs -e ${self.stdenv.cc.libc.out} $out
      '';
    };
    initrd-tools = self.buildEnv {
      name = "initrd-tools";
      paths = [ self.busybox ];
    };
    initrd = self.makeInitrd {
      contents = [
        {
          object = "${self.initrd-tools}/bin";
          symlink = "/bin";
        }
        {
          object = self.script;
          symlink = "/init";
        }
      ];
    };
    test-script = pkgs.writeShellScript "test-script" ''
      #!${self.stdenv.shell}
      ${self.qemu}/bin/qemu-system-x86_64 -kernel ${self.linux}/bzImage -initrd ${self.initrd}/initrd -nographic -append 'console=ttyS0,115200'
    '';
    linuxPackages_4_19 = super.linuxPackages_4_19.extend (lib.const (ksuper: {
      kernel = ksuper.kernel.override {
        configfile = ./kernel.config;
        structuredExtraConfig = with import (pkgs.path + "/lib/kernel.nix") {
          inherit lib;
          inherit (ksuper) version;
        }; {
          #CONFIG_INITRAMFS_SOURCE = "${self.initrd}/initrd";
          #TEST_KMOD = no;
        };
        extraConfig = ''
          INITRAMFS_SOURCE ${self.initrd}
        '';
      };
    }));
  };
  #bootdir = pkgs.runCommand "bootdir" { buildInputs = [ pkgs.dtc ]; } ''
  bootdir = pkgs.runCommand "bootdir" { } ''
    mkdir $out
    cd $out
    echo print-fatal-signals=1 console=ttyAMA0,115200 earlyprintk loglevel=7 root=/dev/mmcblk0p2 printk.devkmsg=on > cmdline.txt
      cp ${pkgs.linux}/bzImage zImage
    echo bootdir is $out
  '';
  helper = pkgs.writeShellScript "helper" ''
    set -e
    set -x
    mount -v /dev/mmcblk0p1 /mnt
    cp -v ${bootdir}/* /mnt/
    ls -ltrh /mnt/
    umount /mnt
  '';
  testcycle = pkgs.writeShellScript "testcycle" ''
    set -e
    exec ${x86_64.uart-manager}/bin/uart-manager
  '';

in rec {
  imports = [ (sources.nixpkgs + "/nixos/modules/profiles/minimal.nix") ];
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
        # devices = [ "nodev" ];
        # supportedFileSystems = [ "ext4" "ext2" "fat32" "f2fs" ];
      };
    };
    kernelPackages = pkgs.linuxPackages_4_19;
    #kernelPackages = linuxPackages_4_4;

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
