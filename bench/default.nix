{ kernelOverride ? null, ... }:
let
  sources = import ./nix/sources.nix;
  busybox = pkgs.pkgsStatic.busybox.override {
    extraConfig = lib.readFile ./fixed.config;
  };
  nixos = (import (sources.nixpkgs + "/nixos") { configuration = ./nixos.nix; });
  rjg-overlay = (import /home/evanjs/src/rjg/nixos/overlay/overlay.nix );
  pkgs = (import sources.nixpkgs { overlays = [ overlay rjg-overlay ]; });
  lib = pkgs.lib;
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
    mylinuxPackages_4_19 = super.linuxPackages_4_19.extend (lib.const (ksuper: {
      kernel = ksuper.kernel.override {
        configfile = ./kernel.config;
        structuredExtraConfig = with import (pkgs.path + "/lib/kernel.nix") {
          inherit lib;
          inherit (ksuper) version;
        }; {
        };
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

in pkgs.lib.fix (self: {
  inherit (nixos) bootdir helper;
  x86_64 = { inherit (x86_64) test-script; };

  kernelShell = nixos.config.boot.kernelPackages.kernel.overrideDerivation
  (drv: {
    nativeBuildInputs = drv.nativeBuildInputs
    ++ (with x86_64; [ ncurses pkgconfig ]);
    shellHook = ''
        addToSearchPath PKG_CONFIG_PATH ${x86_64.ncurses.dev}/lib/pkgconfig
        echo to configure: 'make $makeFlags menuconfig'
        echo to build: 'time make $makeFlags zImage -j8'
    '';
  });
  nixos = {
    inherit nixos;
    inherit (nixos) system;
    inherit (nixos.config.system.build) initialRamdisk;
  };
})
