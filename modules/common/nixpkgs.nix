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
        lldb-mcp-launcher = final.callPackage ../../pkgs/lldb-mcp-launcher.nix {
          lldb = final.unstable.llvmPackages_22.lldb;
          python3 = final.unstable.python3;
        };
        kanata =
          let
            version = "1.12.0-prerelease-2";
            src = final.fetchFromGitHub {
              owner = "FlameFlag";
              repo = "kanata";
              rev = "d188a7570b8fa9cd07b08e5012e82a86cc8f9243";
              hash = "sha256-NSrfKtbxM6AsqGzDPU+ajQq1ucPUlzPv5KQvyYgL9No=";
            };
          in
          prev.kanata.overrideAttrs (old: {
            inherit version src;

            cargoCheckFeatures =
              (old.cargoCheckFeatures or [ ])
              ++ final.lib.lists.optionals final.stdenv.hostPlatform.isLinux [
                "simulated_output"
              ];

            cargoDeps = final.rustPlatform.fetchCargoVendor {
              inherit src;
              name = "kanata-flameflag-2026-06-04";
              hash = "sha256-dVQhiEj8izA4lv4lZdLHr6rND8Gm8pvAx6mP6MPK1zk=";
            };
          });
        kanata-with-cmd = final.kanata.override { withCmd = true; };
        http-fixture = final.callPackage ../../pkgs/http-fixture.nix { };
        ghidra-mcp-headless = final.callPackage ../../pkgs/ghidra-mcp-headless.nix {
          inherit (final.unstable)
            ghidra
            jdk21
            maven
            python313
            ;
        };
        bootstrap = final.callPackage ../../pkgs/bootstrap.nix { };
        lsp-diagnostic-filter = final.callPackage ../../pkgs/lsp-diagnostic-filter.nix { };
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
