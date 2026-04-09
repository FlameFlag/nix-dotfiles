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
        yt-dlp = final.callPackage ../../pkgs/yt-dlp.nix { yt-dlp = final.unstable.yt-dlp; };
        yt-dlp-script = final.callPackage ../../pkgs/yt-dlp-script.nix { };
        gh-hide-comment = final.callPackage ../../pkgs/gh-hide-comment.nix { gh = final.unstable.gh; };
        claude-statusline = final.callPackage ../../pkgs/claude-statusline.nix {
          inherit (final.unstable) rustPlatform;
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
