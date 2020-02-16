{ stdenv
, src
, version
, modDirVersion
, config
, branch
, kernelPatches
# imports
, buildLinux
,   ... } @ args:

with stdenv.lib;

let
  configfile = builtins.storePath (builtins.toFile "config" (lib.concatStringsSep "\n"
    (map (builtins.getAttr "configLine") config.system.requiredKernelConfig))
  );
  patchedKernel = buildLinux (args // rec {
    inherit src version modDirVersion kernelPatches;
        # branchVersion needs to be x.y
        extraMeta.branch = branch;
      } // (args.argsOverride or {}));

    # slightly modify default configurePhase to use our own config with 'allnoconfig'
    configuredKernel = (patchedKernel // (derivation (patchedKernel.drvAttrs // {
      configurePhase = ''
        runHook preConfigure
        mkdir ../build
        make $makeFlags "''${makeFlagsArray[@]}" mrproper
        make $makeFlags "''${makeFlagsArray[@]}" KCONFIG_ALLCONFIG=${configfile} allnoconfig
        runHook postConfigure
      '';
    })));
in
  configuredKernel
