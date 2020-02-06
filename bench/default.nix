{ kernelOverride ? null, ... }:
let
  pkgs = import sources.nixpkgs {};
  sources = import ./nix/sources.nix;
  nixos = (import (sources.nixpkgs + "/nixos") { configuration = ./nixos.nix; });
  x86_64 = import (nixos) x86_64;
in pkgs.lib.fix (self: {
  inherit (nixos) bootdir helper;
  x86_64 = { inherit (pkgs) test-script; };

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
  };
})
