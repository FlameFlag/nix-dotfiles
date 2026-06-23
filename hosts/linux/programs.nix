{ lib, pkgs, ... }:
let
  onePasswordDesktopEntry = ''
    [Desktop Entry]
    Type=Application
    Name=1Password
    Exec=${lib.getExe pkgs._1password-gui} --silent
    Terminal=false
    X-GNOME-Autostart-enabled=true
    NoDisplay=true
  '';
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
        glib
        nss
        nspr
        dbus
        atk
        at-spi2-atk
        at-spi2-core
        cairo
        gtk3
        pango
        libX11
        libXcomposite
        libXdamage
        libXext
        libXfixes
        libXrandr
        libxcb
        libxkbcommon
        systemd
        alsa-lib
        mesa
        libgbm
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

  environment.etc."xdg/autostart/1password.desktop".text = onePasswordDesktopEntry;

  systemd.tmpfiles.rules = lib.lists.optionals (muslDynamicLinker != null) [
    "d /lib 0755 root root - -"
    "L+ /lib/${baseNameOf muslDynamicLinker} - - - - ${muslDynamicLinker}"
    "L+ /lib/libgcc_s.so.1 - - - - ${muslCxxRuntime}/lib/libgcc_s.so.1"
    "L+ /lib/libstdc++.so.6 - - - - ${muslCxxRuntime}/lib/libstdc++.so.6"
  ];
}
