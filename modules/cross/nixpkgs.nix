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
      inputs.scaffold.overlays.default
      (
        final: prev:
        let
          repoRoot = ../..;
          cargoWorkspacePackage =
            {
              package,
              meta ? { },
            }:
            final.rustPlatform.buildRustPackage {
              pname = package;
              version = "0.1.0";

              src = final.lib.fileset.toSource {
                root = repoRoot;
                fileset = final.lib.fileset.unions [
                  (repoRoot + /Cargo.lock)
                  (repoRoot + /Cargo.toml)
                  (repoRoot + /crates)
                  (repoRoot + /packages/system-run-mcp)
                  (repoRoot + /packages/gh-hide-comment)
                  (repoRoot + /packages/http-fixture)
                  (repoRoot + /packages/lenovo-con-mode)
                  (repoRoot + /packages/lsp-diagnostic-filter)
                  (repoRoot + /packages/zellij-theme-tools)
                ];
              };

              cargoLock.lockFile = repoRoot + /Cargo.lock;

              cargoBuildFlags = [
                "--package"
                package
              ];

              cargoTestFlags = [
                "--package"
                package
              ];

              inherit meta;
            };
        in
        {
          gh = final.unstable.gh;
          yt-dlp = final.eupkgs.yt-dlp;
          lldb-mcp-launcher = final.eupkgs.lldb-mcp-launcher;
          kanata =
            let
              version = "1.12.0-prerelease-2";
              src = final.fetchFromGitHub {
                owner = "FlameFlag";
                repo = "kanata";
                rev = "c8c720ded5a34bbc4bdfbfbe33c97b7bb2e60e77";
                hash = "sha256-xnmoRf+xKRSlKPKnCRYsid4laL5+eCD1IP09RjuyjXY=";
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
                name = "kanata-flameflag-2026-06-05";
                hash = "sha256-dVQhiEj8izA4lv4lZdLHr6rND8Gm8pvAx6mP6MPK1zk=";
              };
            });
          kanata-with-cmd = final.kanata.override { withCmd = true; };
          immutable-activate = final.callPackage ../../packages/immutable-activate.nix { };
          immutable-profile = final.callPackage ../../packages/immutable-profile.nix { };
          http-fixture = final.callPackage ../../packages/http-fixture.nix { };
          hyper-window-tiling = final.callPackage ../../packages/hyper-window-tiling.nix { };
          hyper-window-tiling-gnome = final.hyper-window-tiling.gnome;
          hyper-window-tiling-kde = final.hyper-window-tiling.kde;
          chezmoi-support = cargoWorkspacePackage {
            package = "chezmoi-support";
            meta = {
              description = "Dotfiles helper used by chezmoi templates";
              mainProgram = "chezmoi-support";
            };
          };
          gh-hide-comment = cargoWorkspacePackage {
            package = "gh-hide-comment";
            meta = {
              description = "Hide GitHub comments from the command line";
              mainProgram = "gh-hide-comment";
            };
          };
          system-run-mcp = cargoWorkspacePackage {
            package = "system-run-mcp";
            meta = {
              description = "MCP server that runs commands through the local system runner";
              mainProgram = "system-run-mcp";
              platforms = final.lib.platforms.linux ++ final.lib.platforms.darwin;
            };
          };
          ghidra-mcp-headless = final.eupkgs.ghidra-mcp-headless;
          lenovo-con-mode = cargoWorkspacePackage {
            package = "lenovo-con-mode";
            meta = {
              description = "Toggle or set Lenovo Ideapad conservation mode";
              mainProgram = "lenovo-con-mode";
              platforms = final.lib.platforms.linux ++ final.lib.platforms.windows;
            };
          };
          lsp-diagnostic-filter = final.callPackage ../../packages/lsp-diagnostic-filter.nix { };
          zellij-theme-tools = cargoWorkspacePackage {
            package = "zellij-theme-tools";
            meta = {
              description = "Theme helpers for Zellij and Codex sessions";
              platforms = final.lib.platforms.linux ++ final.lib.platforms.darwin;
            };
          };
          dis = inputs.dis.packages.${prev.stdenvNoCC.hostPlatform.system}.dis.overrideAttrs (old: {
            postInstall = ''
              wrapProgram "$out/bin/dis" --prefix PATH : ${final.lib.strings.makeBinPath [ final.yt-dlp ]}
            '';
          });
        }
      )
    ];
  };
}
