{ kernelOverride ? null
, updateKey ? null
, cpioOverride ? null
, hardwareVersion ? "0.0.0"
, softwareVersion ? "0.0.0"
, realtimeRevision ? "unknown"
, ...
}:
let
  sources = import ./nix/sources.nix;
  busybox = pkgs.pkgsStatic.busybox.override {
    extraConfig = lib.readFile ./fixed.config;
  };
  nixos = (
    import (sources.nixpkgs + "/nixos") {
      configuration = ./nixos.nix;
    }
  );

  OVMFFile = "${pkgs.OVMF.fd}/FV/OVMF.fd";
  kernelPackages = pkgs.customLinuxPackages;
  kernel2 = pkgs.customWithInitrd.kernel;
  startupScript = pkgs.writeTextFile {
    name = "startup.nsh";
    text = ''
      fs0:
      \EFI\BOOT\bzImage.efi ro initrd=\EFI\BOOT\initrd
    '';
    executable = true;
  };

  # create a directory with all the contents required to boot into a minimal system
  # kernel, initrd and startup script
  updEFIDir =
    pkgs.runCommand "make-efi-dir" {} ''
      mkdir -p $out/EFI/BOOT
      efidir=$out/EFI/BOOT
      ln -s ${startupScript} $out/startup.nsh
      ln -s ${pkgs.initrd}/initrd $efidir/initrd
      ln -s ${kernel}/bzImage $efidir/bzImage.efi
    '';

  # Compress the EFI directory and wrap it into a mnt/boot directory
  compressedEFIDir =
    pkgs.runCommand "compress-efi-dir" {} ''
      mkdir -p mnt/boot
      mkdir -p $out

      ln -s ${updEFIDir}/* mnt/boot/

      tar -hcaf $out/update.tar.xz mnt/boot
    '';

  deploySensorTesterImage = pkgs.rjg.core-infrastructure.deploy-sensor-tester-image;

  sensorTesterUPDFile =
    assert lib.asserts.assertMsg (updateKey != null) "An update key must be provided when creating a UPD file";
    let
      updateFile = updateKey;
    in
      pkgs.runCommand "make-upd" {} ''
        mkdir $out
        ${pkgs.rjg.core-infrastructure.pack-update_2}/bin/pack_update_2 ${deploySensorTesterImage}/meta_data.zip ${compressedEFIDir}/update.tar.xz $out/stester.upd ${updateFile}
      '';

  pkgs = (import sources.nixpkgs { overlays = [ overlay rjg-overlay ]; });
  kernelVersion = kernel.modDirVersion;
  rjg-overlay = (import ./overlay/overlay.nix);

  rtl8188eu = pkgs.callPackage ./overlay/pkgs/os-specific/linux/rtl8188eu { inherit kernel; };
  kernel = kernelPackages.kernel;

  lib = pkgs.lib;
  x86_64 = pkgs;
  overlay = self: super: {
    customLinuxPackages = pkgs.linuxPackages_4_4.extend (
      lib.const (
        ksuper: {
          kernel = ksuper.kernel.override {
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
              EFIVAR_FS = yes;
            };
            extraConfig = ''
              UEVENT_HELPER_PATH /proc/sys/kernel/hotplug
            '';
          };
        }
      )
    );
    customWithInitrd = self.customLinuxPackages.extend (
      lib.const (
        ksuper: {
          kernel = (
            ksuper.kernel.override {
              extraConfig =
                let
                  initrd-cpio =
                    if cpioOverride != null then "${cpioOverride}" else
                      pkgs.runCommand "initrd-link" {} ''
                        mkdir $out
                        ln -s ${self.initrd}/initrd $out/initrd.cpio
                      '';
                in
                  ''
                    INITRAMFS_SOURCE ${initrd-cpio}/initrd.cpio
                  '';
            }
          );

        }
      )
    );

    # realtime with sensor tester functionality enabled
    realtime = (
      pkgs.pkgsMusl.callPackage ./realtime {
        deploy = false;
        withSensorTester = true;
        withEthercat = false;
        rev = realtimeRevision;
        inherit hardwareVersion softwareVersion;
      }
    );
    script = pkgs.writeTextFile {
      name = "init";
      text = ''
        #!${self.busybox}/bin/busybox
      '';
      executable = true;
    };
    initrd-tools = self.buildEnv {
      name = "initrd-tools";
      paths = [ self.realtime self.busybox pkgs.usbutils pkgs.wirelesstools pkgs.hostapd pkgs.iw pkgs.efibootmgr pkgs.efitools pkgs.efivar ];
    };
    initrd = self.makeInitrd {
      compressor = "xz --check=crc32";
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
          object = "${pkgs.wireless-regdb}/lib/firmware/regulatory.db";
          symlink = "/lib/firmware/regulatory.db";
        }
        {
          object = "${pkgs.wireless-regdb}/lib/firmware/regulatory.db.p7s";
          symlink = "/lib/firmware/regulatory.db.p7s";
        }
      ];
    };
    scripts =
      let
        consoleConfig = "console=ttyS0";

        usb3HubConfig = "-device qemu-xhci,id=xhci -device usb-host,bus=xhci.0";
        usb2HubConfig = "-device usb-ehci,id=ehci -device usb-host,bus=ehci.0";

        # TP-Link TL-WN722N v2
        bigAdapterConfig = ",vendorid=0x2357,productid=0x010c";
        # Realtek Semiconductor Corp. RTL8188EUS 802.11n Wireless Network Adapter
        smallAdapterConfig = ",vendorid=0x0bda,productid=0x8179";

        grubDebugConfig = "-stdio serial -s -S";

        lowMemoryConfig = "-m 1024";
        highMemoryConfig = "-m 4096";

        efiConfig = "-enable-kvm -bios ${OVMFFile}";

        baseConfig = "${self.qemu}/bin/qemu-system-x86_64 -kernel ${kernel}/bzImage -initrd ${self.initrd}/initrd ${usb3HubConfig}";
        baseConfigInitrdInKernel = "${self.qemu}/bin/qemu-system-x86_64 -kernel ${kernel2}/bzImage ${usb3HubConfig}";
      in
        {
          test-script-small-adapter = pkgs.writeShellScript "test-script-small" ''
            #!${self.stdenv.shell}
            ${baseConfig}${smallAdapterConfig} -nographic ${highMemoryConfig} ${efiConfig} -append '${consoleConfig}'
          '';
          test-script-big-adapter = pkgs.writeShellScript "test-script-big" ''
            #!${self.stdenv.shell}
            ${baseConfig}${bigAdapterConfig} -nographic ${highMemoryConfig} ${efiConfig} -append '${consoleConfig}'
          '';
          test-script-big-adapter-embedded-initrd = pkgs.writeShellScript "test-script-big-embedded-initrd" ''
            #!${self.stdenv.shell}
            ${baseConfigInitrdInKernel}${bigAdapterConfig} -nographic ${highMemoryConfig} ${efiConfig} -append '${consoleConfig}'
          '';
          test-script-small-adapter-embedded-initrd = pkgs.writeShellScript "test-script-small-embedded-initrd" ''
            #!${self.stdenv.shell}
            ${baseConfigInitrdInKernel}${smallAdapterConfig} -nographic ${highMemoryConfig} ${efiConfig} -append '${consoleConfig}'
          '';
          test-script-big-adapter-no-efi = pkgs.writeShellScript "test-script-big-no-efi" ''
            #!${self.stdenv.shell}
            ${baseConfig}${bigAdapterConfig} -nographic ${highMemoryConfig} -append '${consoleConfig}'
          '';
          debug-script = pkgs.writeShellScript "debug-script" ''
            #!${self.stdenv.shell}
            ${baseConfig} -nographic ${highMemoryConfig} ${efiConfig} -append '${consoleConfig} ${grubDebugConfig}'
          '';
          startup-script = pkgs.writeShellScript "startup-script" ''
            #!${self.stdenv.shell}
            ${self.qemu}/bin/qemu-system-x86_64 ${usb3HubConfig}${smallAdapterConfig} -nographic ${highMemoryConfig} -drive format=raw,file=fat:rw:${updEFIDir} -net none -drive if=pflash,format=raw,readonly,file=${OVMFFile}
          '';
        };
  };
in
pkgs.lib.fix (
  self: {
    x86_64 = { inherit (x86_64) scripts; };
    inherit (pkgs) realtime;
    inherit kernel kernel2;
    inherit sensorTesterUPDFile updEFIDir startupScript compressedEFIDir;

    kernelShell = kernelPackages.kernel.overrideDerivation
      (
        drv: {
          nativeBuildInputs = drv.nativeBuildInputs
          ++ (with x86_64; [ ncurses pkgconfig ]);
          shellHook = ''
            addToSearchPath PKG_CONFIG_PATH ${x86_64.ncurses.dev}/lib/pkgconfig
            echo to configure: 'make $makeFlags menuconfig'
            echo to build: 'time make $makeFlags zImage -j8'
          '';
        }
      );
    kernelShellLight = pkgs.writeShellScript "kshell" ''
      nix-shell -E 'with import <nixpkgs> {}; linux_4_4.overrideAttrs (o: {nativeBuildInputs=o.nativeBuildInputs ++ [ pkgconfig ncurses ];})'
    '';
    inherit (pkgs) initrd;
    inherit pkgs;
    nixos = {
      inherit (nixos) system;
      inherit (nixos.config.system.build) initialRamdisk;
    };
  }
)
