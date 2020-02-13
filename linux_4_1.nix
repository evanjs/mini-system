{ pkgs, lib, linuxPackages, linuxPackagesFor, buildLinux, fetchurl, ... } @ args:

  buildLinux (args // rec {
    version = "4.1.8";
    modDirVersion = version;

    src = fetchurl {
      url = "mirror://kernel/linux/kernel/v4.x/linux-${version}.tar.xz";
      sha256 = "127nv00w5b8168vd3ajypl3w1z8zgyq327gzb66prv19p4abj1q5";
    };

    kernelPatches = [];

    structuredExtraConfig = with import (pkgs.path + "/lib/kernel.nix") {
      inherit lib;
      #inherit (base) version;
      version = "4.1.8";
    }; {
      USB_EHCI_PCI = yes;
      USB_XHCI_PCI = yes;
      RTL8188EU = yes;
      RFKILL = yes;
      EXFAT_FS = lib.mkForce no;
    };

    extraMeta.branch = "4.1";
  } // (args.argsOverride or {}))
