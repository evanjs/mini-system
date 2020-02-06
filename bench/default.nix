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
        #!/bin/sh
        ln -sf /dev/null /dev/tty2
        ln -sf /dev/null /dev/tty3
        ln -sf /dev/null /dev/tty4
        ${busybox}/bin/ash
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
