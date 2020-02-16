{ kernelOverride ? null, ... }:
let
  sources = import ./nix/sources.nix;
  busybox = pkgs.pkgsStatic.busybox.override {
    extraConfig = lib.readFile ./fixed.config;
  };
  nixos = (import (sources.nixpkgs + "/nixos") {
    configuration = ./nixos.nix;
  });

  kernelPackages = pkgs.customLinuxPackages;
  kernel2 = pkgs.customWithInitrd.kernel;

  pkgs = (import sources.nixpkgs { overlays = [ overlay ]; });
  local = (import /home/evanjs/src/nixpkgs { overlays = [ rjg-overlay]; });
  kernelVersion = kernel.modDirVersion;
  rjg-overlay = (import /home/evanjs/src/rjg/nixos/overlay/overlay.nix );
  hostapd = pkgs.callPackage ./hostapd { };

  rtl8188eu = pkgs.callPackage /home/evanjs/src/nixpkgs/pkgs/os-specific/linux/rtl8188eu { inherit kernel; };

  kernel = kernelPackages.kernel;


  #modulesClosure = local.makeModulesClosure {
    #inherit kernel rootModules;
    #firmware = kernel;
  #};

  lib = pkgs.lib;
  x86_64 = pkgs;
  overlay = self: super: {
    customLinuxPackages = local.linuxPackages_4_4.extend ( lib.const (ksuper: {
      kernel = ksuper.kernel.override {
        configfile = ./linux/kernel.config;
        structuredExtraConfig = with import (pkgs.path + "/lib/kernel.nix") {
          inherit lib;
          inherit (ksuper) version;
        }; {
          CFG80211 = yes;
          PACKET = yes;
          RFKILL = yes;
          USB = yes;
          USB_COMMON = yes;
          USB_EHCI_HCD = yes;
          USB_XHCI_HCD = yes;
          UEVENT_HELPER = yes;
        };
        extraConfig = ''
          UEVENT_HELPER_PATH /proc/sys/kernel/hotplug
        '';
      };
    }));
    customWithInitrd = self.customLinuxPackages.extend (lib.const (ksuper: {
      kernel = ksuper.kernel.override {
        configfile = ./linux/kernel.config;
        extraConfig = ''
          INITRAMFS_SOURCE ${self.initrd}
          BLK_DEV_INITRD y
        '';
      };
    }));
    realtime = (pkgs.pkgsMusl.callPackage ./realtime {
      deploy = false;
      withSensorTester = true;
      withEthercat = false;
      softwareVersion = "5.0.0";
      hardwareVersion = "10.0.0";
    });
    script = pkgs.writeTextFile {
      name = "init";
      text = ''
        #!${self.busybox}/bin/busybox
      '';
      executable = true;
    };
    initrd-tools = self.buildEnv {
      name = "initrd-tools";
      paths = [ self.realtime self.busybox pkgs.usbutils pkgs.wirelesstools pkgs.hostapd pkgs.iw ];
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
          object = "${rtl8188eu}/lib/modules";
          symlink = "/lib/modules";
        }
        {
          object = "${pkgs.rtlwifi_new-firmware}/lib/firmware";
          symlink = "/lib/firmware/rtlwifi";
        }
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

        usb3AdapterConfig = "-device qemu-xhci,id=xhci -device usb-host,bus=xhci.0,vendorid=0x2357,productid=0x010c";
        usb2AdapterConfig = "-device usb-ehci,id=ehci -device usb-host,bus=ehci.0,vendorid=0x2357,productid=0x010c";

        grubDebugConfig = "-stdio serial -s -S";

        lowMemoryConfig = "-m 1024";
        highMemoryConfig = "-m 4096";

        baseConfig = "${self.qemu}/bin/qemu-system-x86_64 -kernel ${kernel2}/bzImage -initrd ${self.initrd}/initrd ${usb3AdapterConfig}";
        baseConfigInitrdInKernel = "${self.qemu}/bin/qemu-system-x86_64 -kernel ${kernel2}/bzImage ${usb3AdapterConfig}";
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
        test-script-builtin-initrd = pkgs.writeShellScript "kernel-with-initrd" ''
      #!${self.stdenv.shell}
          ${baseConfigInitrdInKernel} -nographic ${highMemoryConfig} -append '${consoleConfig}'
        '';
      };
    };
    #rootModules = [
      ##"rtl8188eu"
      #"rtl8192"
      #"cfg80211"
      #"usbhid"
      #"xhci_hcd"
      #"ehci_hcd"
      #"xhci_pci"
      #"ehci_pci"
      #"af_packet"
    #];

in pkgs.lib.fix (self: {
  x86_64 = { inherit (x86_64) scripts; };
  inherit kernel kernel2;

  kernelShell = kernelPackages.kernel.overrideDerivation
  (drv: {
    nativeBuildInputs = drv.nativeBuildInputs
    ++ (with x86_64; [ ncurses pkgconfig ]);
    shellHook = ''
      addToSearchPath PKG_CONFIG_PATH ${x86_64.ncurses.dev}/lib/pkgconfig
      echo to configure: 'make $makeFlags menuconfig'
      echo to build: 'time make $makeFlags zImage -j8'
    '';
  });
  kernelShellLight = pkgs.writeShellScript "kshell" ''
    nix-shell -E 'with import <nixpkgs> {}; linux_4_4.overrideAttrs (o: {nativeBuildInputs=o.nativeBuildInputs ++ [ pkgconfig ncurses ];})'
  '';
  inherit (pkgs) initrd;
  nixos = {
    inherit (nixos) system;
    inherit (nixos.config.system.build) initialRamdisk;
  };
})
