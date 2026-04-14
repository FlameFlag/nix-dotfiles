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
        yt-dlp = final.eupkgs.yt-dlp;
        gh-hide-comment = final.callPackage ../../pkgs/gh-hide-comment.nix {
          gh = final.unstable.gh;
          nushell = final.unstable.nushell;
        };
        dis = inputs.dis.packages.${prev.stdenvNoCC.hostPlatform.system}.dis.overrideAttrs (old: {
          postInstall = ''
            wrapProgram "$out/bin/dis" \
              --prefix PATH : ${
                final.lib.makeBinPath [
                  final.ffmpeg-full
                  final.yt-dlp
                ]
              }
          '';
        });
      })
    ];
  };
}
