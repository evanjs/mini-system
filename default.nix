{ kernelOverride ? null, ... }:
let
  sources = import ./nix/sources.nix;
  busybox = pkgs.pkgsStatic.busybox.override {
    extraConfig = lib.readFile ./fixed.config;
  };
  stdenv = pkgs.pkgsMusl.stdenv;
  nixos = (import (sources.nixpkgs + "/nixos") { configuration = ./nixos.nix; });
  #nixos = (import <nixpkgs/nixos> { configuration = ./nixos.nix; });
  pkgs = (import sources.nixpkgs { overlays = [ overlay ]; });
  #pkgs = (import /home/evanjs/src/nixpkgs { overlays = [ overlay ]; });
  inherit (nixos.config.system.build) kernel;

  lib = pkgs.lib;
  x86_64 = pkgs;
  overlay = self: super: {
    realtime = (pkgs.callPackage ./realtime {
      deploy = false;
      withSensorTester = true;
      withEthercat = false;
      softwareVersion = "5.0.0";
      hardwareVersion = "10.0.0";
      inherit stdenv;
    });
    uart-manager = self.stdenv.mkDerivation {
      name = "uart-manager";
      src = ./uart-manager;
    };
    script = pkgs.writeTextFile {
      name = "init";
      text = ''
        #!${self.busybox}/bin/busybox
      '';
      executable = true;
    };
    initrd-tools = self.buildEnv {
      name = "initrd-tools";
      paths = [ self.realtime self.busybox pkgs.usbutils ];
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
        {
          object = ./rootfs/etc;
          symlink = "/etc";
        }
        {
          object = ./rootfs/lib/firmware;
          symlink = "/lib/firmware";
        }
        {
          object = "${self.linux}/lib/modules";
          symlink = "/lib/modules";
        }
      ];
      };
      scripts =
        let
          consoleConfig = "console=ttyS0";
        #busConfig = ''
          #-device ich9-usb-ehci1,id=usb,bus=pci.0,addr=0x5.0x7 \
          #-device ich9-usb-uhci3,masterbus=usb.0,firstport=4,bus=pci.0,addr=0x5.0x2 \
        #'';
        #usbAdapterConfig = "${busConfig} -device usb-host,hostbus=2,hostaddr=2,id=hostdev0,bus=usb.0,port=4";
        grubDebugConfig = "-stdio serial -s -S";
        memoryConfig = "-m 4096";
        baseConfig = "${self.qemu}/bin/qemu-system-x86_64 -kernel ${self.linux}/bzImage -initrd ${self.initrd}/initrd";
        in
        {
          test-script-small-adapter = pkgs.writeShellScript "test-script-small" ''
      #!${self.stdenv.shell}
            ${baseConfig} -nographic ${memoryConfig} -append '${consoleConfig}'
          '';
          test-script-big-adapter = pkgs.writeShellScript "test-script-big" ''
      #!${self.stdenv.shell}
            ${baseConfig} -nographic ${memoryConfig} -append '${consoleConfig}'
          '';
          debug-script = pkgs.writeShellScript "debug-script" ''
      #!${self.stdenv.shell}
            ${baseConfig} -nographic ${memoryConfig} -append '${consoleConfig} ${grubDebugConfig}'
          '';
        };
      };
      rootModules = [
      #"rtl8188ee"
      "rtlwifi"
      "xhci_pci"
      "ehci_pci"
      "ahci"
      "usbhid"
      "usb_storage"
      "sd_mod"
    ];
    modulesClosure = pkgs.makeModulesClosure {
      inherit kernel;
      inherit rootModules;
      firmware = kernel;
    };

in pkgs.lib.fix (self: {
  x86_64 = { inherit (x86_64) scripts; };

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
  inherit (pkgs) initrd;
  nixos = {
    inherit nixos;
    #inherit modulesClosure;
    inherit (kernel) dev;
    inherit (nixos) system;
    inherit (nixos.config.system.build) initialRamdisk;
  };
})
