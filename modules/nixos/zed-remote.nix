{ lib, pkgs, ... }:
{
  systemd.tmpfiles.rules =
    let
      inherit (pkgs.zed-editor.remote_server) version;
      binaryName = "zed-remote-server-stable-${version}";
    in
    [
      "d /home/nyx/.zed_server 0755 nyx users - -"
      "L+ /home/nyx/.zed_server/${binaryName} - - - - ${lib.getExe' pkgs.zed-editor.remote_server binaryName}"
    ];
}
