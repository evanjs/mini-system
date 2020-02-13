{ kernelOverride ? null, ... }:
let
  #sources = import ./nix/sources.nix;
  busybox = pkgs.pkgsStatic.busybox.override {
    extraConfig = lib.readFile ./fixed.config;
  };
  stdenv = pkgs.pkgsMusl.stdenv;
  #nixos = (import (sources.nixpkgs + "/nixos") { configuration = ./nixos.nix; });
  nixos = (import <nixpkgs/nixos> { configuration = ./nixos.nix; });

  #pkgs = (import sources.nixpkgs { overlays = [ overlay ]; });
  pkgs = (import /home/evanjs/src/nixpkgs { overlays = [ overlay ]; });
  kernelVersion = kernel.modDirVersion;

  inherit (nixos.config.boot.kernelPackages) kernel;
  inherit (nixos.config.boot) kernelPackages;

  modulesClosure = pkgs.makeModulesClosure {
    inherit kernel;
    inherit rootModules;
    firmware = kernel;
    allowMissing = true;
  };

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
      paths = [ self.realtime self.busybox pkgs.usbutils pkgs.hostapd pkgs.wirelesstools ];
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
        #{
          #object = "${kernelPackages.rtl8188eu}/lib/modules/${kernelVersion}/kernel/drivers/net";
          #symlink = "/lib/modules/${kernelVersion}/kernel/drivers/net";
        #}
        #{
          #object = "${modulesClosure}/lib/modules/${kernelVersion}/kernel/net/rfkill";
          #symlink = "/lib/modules/${kernelVersion}/kernel/net/rfkill";
        #}
        #{
          #object = "${modulesClosure}/lib/modules/${kernelVersion}/kernel/net/wireless";
          #symlink = "/lib/modules/${kernelVersion}/kernel/net/wireless";
        #}
        #{
          #object = "${modulesClosure}/lib/modules/${kernelVersion}/kernel/drivers/hid";
          #symlink = "/lib/modules/${kernelVersion}/kernel/drivers/hid";
        #}
        #{
          #object = "${modulesClosure}/lib/modules/${kernelVersion}/kernel/drivers/scsi";
          #symlink = "/lib/modules/${kernelVersion}/kernel/drivers/scsi";
        #}
        #{
          #object = "${modulesClosure}/lib/modules/${kernelVersion}/modules*";
          #symlink = "/lib/modules/${kernelVersion}/";
        #}
        #{
          #object = "${modulesClosure}/lib/modules/";
          #symlink = "/lib/modules";
        #}

        {
          object = "${kernel}/lib/modules/";
          symlink = "/lib/modules";
        }
         
          #object = "${pkgs.rtlwifi_new-firmware}/lib/firmware";
          #symlink = "/lib/firmware/rtlwifi";
        #}
        {
          object= "${pkgs.wireless-regdb}/lib/firmware/regulatory.db";
          symlink = "/lib/firmware/regulatory.db";
        }
        {
          object= "${pkgs.wireless-regdb}/lib/firmware/regulatory.db.p7s";
          symlink = "/lib/firmware/regulatory.db.p7s";
        }
      ];
    };
    scripts =
      let
        consoleConfig = "console=ttyS0";
        #busConfig = ''
          #-device ich9-usb-ehci1,id=usb,bus=pci.0,addr=0x5.0x7 \o
          #-device ich9-usb-uhci3,masterbus=usb.0,firstport=4,bus=pci.0,addr=0x5.0x2 \
        #'';
        #usbAdapterConfig = "${busConfig} -device usb-host,hostbus=2,hostaddr=2,id=hostdev0,bus=usb.0,port=4";
        usb3AdapterConfig = "-device qemu-xhci,id=xhci -device usb-host,bus=xhci.0,vendorid=0x2357,productid=0x010c";
        usb2AdapterConfig = "-device usb-ehci,id=ehci -device usb-host,bus=ehci.0,vendorid=0x2357,productid=0x010c";
        grubDebugConfig = "-stdio serial -s -S";
        lowMemoryConfig = "-m 4096";
        highMemoryConfig = "-m 2048";
        baseConfig = "${self.qemu}/bin/qemu-system-x86_64 -kernel ${kernel}/bzImage -initrd ${self.initrd}/initrd ${usb3AdapterConfig}";
      in
      {
        test-script-small-adapter = pkgs.writeShellScript "test-script-small" ''
      #!${self.stdenv.shell}
            ${baseConfig} -nographic ${highMemoryConfig} -append '${consoleConfig}'
        '';
        test-script-big-adapter = pkgs.writeShellScript "test-script-big" ''
      #!${self.stdenv.shell}
            ${baseConfig} -nographic ${highMemoryConfig} -append '${consoleConfig}'
        '';
        debug-script = pkgs.writeShellScript "debug-script" ''
      #!${self.stdenv.shell}
            ${baseConfig} -nographic ${highMemoryConfig} -append '${consoleConfig} ${grubDebugConfig}'
        '';
      };
    };
    rootModules = [
      #"rtl8188ee"
      #"rtl8188eu"
      #"rtl8192"
      "rtlwifi"
      "sd_mod"
      "usbhid"
      "xhci_hcd"
      "ehci_hcd"
      "xhci_pci"
      "ehci_pci"
    ];

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
    #inherit (pkgs) initrd;


    inherit modulesClosure;
    #config = import nixos.config { initrd = { prepend = self.initrd.contents; }; };
    inherit (nixos) config;

    #initrd = self.nixos.config.boot.initrd.prepend initrd;
    #config.boot.initrd.prepend = initrd;

    inherit (kernel) dev;
    inherit (nixos) system;
    inherit (nixos.config.system.build) initialRamdisk;
  };
})
