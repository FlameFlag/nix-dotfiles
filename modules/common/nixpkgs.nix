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
        unstable = prev.unstable.extend (
          ufinal: uprev: {
            yazi-unwrapped = uprev.yazi-unwrapped.overrideAttrs (old: rec {
              version = "26.5.6";

              srcs = builtins.attrValues passthru.srcs;
              sourceRoot = passthru.srcs.code_src.name;
              cargoHash = "sha256-HlMrv4NGSFFrsc3fm4OeiGcKpCTnwTdgVV792TU2hGk=";
              cargoDeps = ufinal.rustPlatform.fetchCargoVendor {
                inherit srcs sourceRoot;
                hash = cargoHash;
              };

              env = (old.env or { }) // {
                VERGEN_GIT_SHA = "3f5cc47a4852";
                VERGEN_BUILD_DATE = "2026-05-15";
              };

              postPatch = ''
                substituteInPlace Cargo.toml \
                  --replace-fail 'rust-version = "1.95.0"' 'rust-version = "1.94.1"'

                substituteInPlace yazi-config/src/theme/icon.rs \
                  --replace-fail 'true if let Some(i) = self.dirs.matches(name) => Some(i),' 'true => self.dirs.matches(name).or_else(|| self.conds.matches(file, hovered)),' \
                  --replace-fail 'false if let Some(i) = self.files.matches(name) => Some(i),' 'false => self.files.matches(name)' \
                  --replace-fail 'false if let Some(i) = self.exts.matches(file.url.ext().unwrap_or_default()) => Some(i),' '.or_else(|| self.exts.matches(file.url.ext().unwrap_or_default())).or_else(|| self.conds.matches(file, hovered)),' \
                  --replace-fail '_ => self.conds.matches(file, hovered),' ""
              '';

              passthru = (old.passthru or { }) // {
                srcs = (old.passthru.srcs or { }) // {
                  code_src = ufinal.fetchFromGitHub {
                    owner = "sxyazi";
                    repo = "yazi";
                    rev = "3f5cc47a4852cbffbd8536507ae7499d3da1f0b7";
                    hash = "sha256-TtawbMZ+tgKAiDpkJJw7m2OLOJHUbRZB0xLDXBxTPck=";
                  };
                };
              };
            });

            yazi = uprev.yazi.override {
              yazi-unwrapped = ufinal.yazi-unwrapped;
            };
          }
        );
      })
      (final: prev: {
        eupkgs = final.unstable.extend inputs.eupkgs.overlays.default;
      })
      (final: prev: {
        gh = final.unstable.gh;
        yt-dlp = final.eupkgs.yt-dlp;
        codex-lldb-mcp = final.callPackage ../../pkgs/codex-lldb-mcp.nix {
          lldb = final.unstable.llvmPackages_22.lldb;
          python3 = final.unstable.python3;
        };
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

            cargoCheckFeatures =
              (old.cargoCheckFeatures or [ ])
              ++ final.lib.lists.optionals final.stdenv.hostPlatform.isLinux [
                "simulated_output"
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
