{ inputs, ... }:
{
  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      (final: prev: {
        unstable = import inputs.nixpkgs-unstable {
          inherit (prev.stdenvNoCC.hostPlatform) system;
          inherit (prev) config;
        };
      })
      (final: prev: {
        eupkgs = final.unstable.extend inputs.eupkgs.overlays.default;
      })
      (final: prev: {
        zig = final.unstable.zig;
        gh = final.unstable.gh;
        yt-dlp = final.eupkgs.yt-dlp;
        kanata-with-cmd = final.kanata.override { withCmd = true; };
        gh-hide-comment = final.callPackage ../../pkgs/gh-hide-comment.nix { };
        lenovo-con-mode = final.callPackage ../../pkgs/lenovo-con-mode.nix { };
        ziglint = final.callPackage ../../pkgs/ziglint.nix { };
        ghidra-mcp-headless = final.callPackage ../../pkgs/ghidra-mcp-headless.nix {
          inherit (final.unstable)
            ghidra
            jdk21
            maven
            python313
            ;
        };
        dis = inputs.dis.packages.${prev.stdenvNoCC.hostPlatform.system}.dis.overrideAttrs (old: {
          postInstall = ''
            wrapProgram "$out/bin/dis" \
              --prefix PATH : ${
                final.lib.makeBinPath [
                  final.ffmpeg
                  final.yt-dlp
                ]
              }
          '';
        });
      })
    ];
  };
}
