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
        gh = final.unstable.gh;
        yt-dlp = final.eupkgs.yt-dlp;
        kanata =
          let
            version = "1.12.0-prerelease-2";
            src = final.fetchFromGitHub {
              owner = "jtroo";
              repo = "kanata";
              rev = "c4e07fbb39b28a18dca4a2234e65793bef526f99";
              hash = "sha256-dcwMOAptUhmbnlpxBHS9bimvV4IPmhHd4qtcunJ05h8=";
            };
          in
          prev.kanata.overrideAttrs (old: {
            inherit version src;

            patches = (old.patches or [ ]) ++ [
              ../../pkgs/patches/kanata-macos-window-dsl.patch
            ];

            cargoDeps = final.rustPlatform.fetchCargoVendor {
              inherit src;
              name = "kanata-unstable-2026-05-09";
              hash = "sha256-dVQhiEj8izA4lv4lZdLHr6rND8Gm8pvAx6mP6MPK1zk=";
            };
          });
        kanata-with-cmd = final.kanata.override { withCmd = true; };
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
                final.lib.strings.makeBinPath [
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
