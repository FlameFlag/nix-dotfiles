{ lib, pkgs, ... }:
let
  muslCxxRuntime = pkgs.pkgsMusl.stdenv.cc.cc.lib;
  muslDynamicLinker =
    {
      aarch64-linux = "${pkgs.musl}/lib/ld-musl-aarch64.so.1";
      x86_64-linux = "${pkgs.musl}/lib/ld-musl-x86_64.so.1";
    }
    .${pkgs.stdenv.hostPlatform.system} or null;
in
{
  programs = {
    chromium.enable = true;
    nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        glibc
        zlib
        openssl
        curl
        expat
        libxcrypt
        bzip2
        xz
        libffi
        sqlite
        ncurses
        readline
      ];
    };
    _1password.enable = true;
    _1password-gui = {
      enable = true;
      polkitPolicyOwners = [ "nyx" ];
    };
  };

  systemd.tmpfiles.rules = lib.lists.optionals (muslDynamicLinker != null) [
    "d /lib 0755 root root - -"
    "L+ /lib/${baseNameOf muslDynamicLinker} - - - - ${muslDynamicLinker}"
    "L+ /lib/libgcc_s.so.1 - - - - ${muslCxxRuntime}/lib/libgcc_s.so.1"
    "L+ /lib/libstdc++.so.6 - - - - ${muslCxxRuntime}/lib/libstdc++.so.6"
  ];
}
