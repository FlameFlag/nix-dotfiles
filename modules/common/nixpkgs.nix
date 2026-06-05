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
                  (repoRoot + /bootstrap)
                  (repoRoot + /crates)
                  (repoRoot + /pkgs/gh-hide-comment)
                  (repoRoot + /pkgs/http-fixture)
                  (repoRoot + /pkgs/lenovo-con-mode)
                  (repoRoot + /pkgs/lsp-diagnostic-filter)
                  (repoRoot + /pkgs/zellij-theme-tools)
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
          ghidra-mcp-headless = final.callPackage ../../pkgs/ghidra-mcp-headless.nix {
            inherit (final.unstable)
              ghidra
              jdk21
              maven
              python313
              ;
          };
          lenovo-con-mode = cargoWorkspacePackage {
            package = "lenovo-con-mode";
            meta = {
              description = "Toggle or set Lenovo Ideapad conservation mode";
              mainProgram = "lenovo-con-mode";
              platforms = final.lib.platforms.linux ++ final.lib.platforms.windows;
            };
          };
          bootstrap = final.callPackage ../../pkgs/bootstrap.nix { };
          lsp-diagnostic-filter = final.callPackage ../../pkgs/lsp-diagnostic-filter.nix { };
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
