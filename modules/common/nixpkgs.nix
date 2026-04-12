{ inputs, config, ... }:
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
        eupkgs = inputs.eupkgs.legacyPackages.${prev.stdenv.hostPlatform.system} // {
          claude-code = final.unstable.callPackage
            "${inputs.eupkgs}/pkgs/by-name/cl/claude-code/package.nix" { };
        };
      })
      (final: prev: {
        yt-dlp = final.eupkgs.yt-dlp;
        gh-hide-comment = final.callPackage ../../pkgs/gh-hide-comment.nix { gh = final.unstable.gh; };
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
