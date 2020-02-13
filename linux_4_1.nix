{ pkgs, ... }:
let
  base = pkgs.linuxPackages.kernel;
  linuxPackages_4_1 = { fetchurl, buildLinux, lib, ... } @ args:

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
      inherit version;
    }; {
      USB_EHCI_PCI = yes;
      USB_XHCI_PCI = yes;
      RTL8188EU = yes;
      RFKILL = yes;
    };

    extraMeta.branch = "4.1";
  } // (args.argsOverride or {}));
  linux_4_1 = pkgs.callPackage linuxPackages_4_1 {};
in
  pkgs.recurseIntoAttrs (pkgs.linuxPackagesFor linux_4_1)
