{ kernelOverride ? null
}:

let
  sources = import ./nix/sources.nix;
  pkgs = import sources.nixpkgs {};
  lib = pkgs.lib;
  nixos = (import (sources.nixpkgs + "/nixos") { configuration = ./nixos.nix; });
  x86_64 = pkgs.extend overlay;
  overlay = self: super: {
    test-script = pkgs.writeShellScript "test-script" ''
      #!${self.stdenv.shell}
      ${self.qemu}/bin/qemu-system-x86_64 -kernel ${self.linux}/bzImage -initrd ${self.initrd}/initrd -nographic -append 'console=ttyS0,115200'
    '';
    initrd-tools = self.buildEnv {
      name = "initrd-tools";
      path = [ self.busybox ];
    };
    initrd = self.makeInitrd {
      contents = [
        {
          object = "${self.initrd-tools}/bin";
          symlink = "/bin";
        }
      ];
    };
  };
in pkgs.lib.fix (self: {
  x86_64 = {
    inherit (x86_64) test-script;
  };
  # make $makeFlags menuconfig

  nixos = {
    inherit (nixos) system;
    inherit (nixos.config.system.build) initialRamdisk;
  };
})
