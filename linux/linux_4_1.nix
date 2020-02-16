{ pkgs, lib, linuxPackages, linuxPackagesFor, buildLinux, fetchurl, ... } @ args:

  buildLinux (args // rec {
    version = "4.1.8";
    modDirVersion = version;

    src = fetchurl {
      url = "mirror://kernel/linux/kernel/v4.x/linux-${version}.tar.xz";
      sha256 = "1zhck5892c3anbifq3d0ngy40zm9q4c651kgkjk9wf32jjpnngar";
    };

    kernelPatches = [];

    extraMeta.branch = "4.1";
  } // (args.argsOverride or {}))
