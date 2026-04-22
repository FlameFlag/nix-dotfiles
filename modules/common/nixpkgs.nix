{ inputs, ... }:
let
  kanataLatest =
    final: pkg:
    let
      src = final.fetchFromGitHub {
        owner = "jtroo";
        repo = "kanata";
        rev = "ec48fe37898326cfc79b1cf8e27f91e37112eb45";
        hash = "sha256-LP2NE7rh7Brc2DFPKwh5wJGMmbnBDbggaURSVXbpsUY=";
      };
    in
    pkg.overrideAttrs (_old: {
      version = "1.9.0-unstable-2026-04-26";
      inherit src;
      patches = (_old.patches or [ ]) ++ [
        ../../pkgs/kanata/patches/0001-fix-macos-sync-caps-led-and-suppress-side-buttons.patch
        ../../pkgs/kanata/patches/0002-fix-macos-handle-volume-keys-with-coreaudio.patch
      ];
      cargoHash = null;
      cargoDeps = final.rustPlatform.fetchCargoVendor {
        inherit src;
        hash = "sha256-LYx0vNy42OPt+dnCU6Ni6myMsMuIlRyuGon6R1yPpHw=";
      };
      doInstallCheck = false;
    });
in
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
        kanata = kanataLatest final prev.kanata;
        kanata-with-cmd = final.kanata.override { withCmd = true; };
        gh-hide-comment = final.callPackage ../../pkgs/gh-hide-comment.nix {
          gh = final.unstable.gh;
          nushell = final.unstable.nushell;
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
