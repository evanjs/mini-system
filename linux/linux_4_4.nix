{ stdenv, callPackage, fetchurl, modDirVersionArg ? null, ... } @ args:

with stdenv.lib;

let
  configfile = ./kernel.config;

  kernelPatches = [];

  version = "4.4.209";
  branch = versions.majorMinor version;
  src = fetchurl {
    url = "mirror://kernel/linux/kernel/v4.x/linux-${version}.tar.xz";
    sha256 = "0m94795grq3sbj7jlmwc0ncq3vap9lf1z00sdiys17kjs3bcfbnh";
  };

  modDirVersion = if (modDirVersionArg == null) then concatStringsSep "." (take 3 (splitVersion "${version}.0")) else modDirVersionArg;

in
  (callPackage ./generic_linux.nix (args // {
    inherit src version modDirVersion configfile kernelPatches branch;
  }))
