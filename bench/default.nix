{ kernelOverride ? null, ... }:
let
  sources = import ./nix/sources.nix;
  busybox = pkgs.pkgsStatic.busybox.override {
    extraConfig = lib.readFile ./fixed.config;
  };
  nixos = (import (sources.nixpkgs + "/nixos") { configuration = ./nixos.nix; });
  pkgs = (import sources.nixpkgs { overlays = [ overlay ]; });
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
        exec > /dev/ttyS0 2>&1 < /dev/ttyS0
        /bin/ash > /dev/ttyS0 < /dev/ttyS0
        echo ash failed
      '';
      executable = true;
    };
    initrd-tools = self.buildEnv {
      name = "initrd-tools";
      paths = [ busybox ];
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
      ${self.qemu}/bin/qemu-system-x86_64 -kernel ${self.linux}/bzImage -initrd ${self.initrd}/initrd -nographic -append 'console=ttyS0'
    '';
    debug-script = pkgs.writeShellScript "debug-script" ''
      #!${self.stdenv.shell}
      ${self.qemu}/bin/qemu-system-x86_64 -kernel ${self.linux}/bzImage -initrd ${self.initrd}/initrd -nographic -append 'console=ttyS0 -stdio serial -s -S'
    '';
  };

in pkgs.lib.fix (self: {
  x86_64 = { inherit (x86_64) debug-script test-script; };

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
    inherit (nixos.config.system.build.kernel) dev;
  };
})
