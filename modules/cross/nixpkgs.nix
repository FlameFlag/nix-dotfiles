{ inputs, ... }:
{
  _class = null;

  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      (
        final: prev:
        let
          unstable = import inputs.nixpkgs-unstable {
            inherit (prev.stdenvNoCC.hostPlatform) system;
            inherit (prev) config;
          };
          eupkgsScope =
            unstable
            // eupkgsOverlay
            // {
              callPackage = unstable.lib.callPackageWith eupkgsScope;
            };
          eupkgsOverlay = inputs.eupkgs.overlays.default eupkgsScope unstable;
          eupkgs = builtins.removeAttrs eupkgsOverlay [ "_internalCallByNamePackageFile" ];
        in
        {
          inherit unstable eupkgs;
        }
      )
      (
        final: prev:
        let
          goWorkspacePackage = final.callPackage ../../packages/go-workspace-package.nix { };
        in
        {
          gh = final.unstable.gh;
          yt-dlp = final.eupkgs.yt-dlp;
          lldb-mcp-launcher = final.eupkgs.lldb-mcp-launcher;
          kanata =
            if final.stdenv.hostPlatform.isDarwin then
              let
                version = "1.12.0-prerelease-2";
                src = final.fetchFromGitHub {
                  owner = "FlameFlag";
                  repo = "kanata";
                  rev = "c8c720ded5a34bbc4bdfbfbe33c97b7bb2e60e77";
                  hash = "sha256-xnmoRf+xKRSlKPKnCRYsid4laL5+eCD1IP09RjuyjXY=";
                };
              in
              prev.kanata.overrideAttrs {
                inherit version src;

                cargoDeps = final.rustPlatform.fetchCargoVendor {
                  inherit src;
                  name = "kanata-flameflag-2026-06-05";
                  hash = "sha256-dVQhiEj8izA4lv4lZdLHr6rND8Gm8pvAx6mP6MPK1zk=";
                };
              }
            else
              prev.kanata;
          kanata-with-cmd = final.kanata.override { withCmd = true; };
          immutable-activate = final.callPackage ../../packages/immutable-activate.nix { };
          linux-toolbox-profile = final.callPackage ../../packages/linux-toolbox-profile.nix { };
          portable-linux-profile = final.callPackage ../../packages/portable-linux-profile.nix { };
          http-fixture = final.callPackage ../../packages/http-fixture.nix { };
          hyper-window-tiling = final.callPackage ../../packages/hyper-window-tiling.nix { };
          hyper-window-tiling-gnome = final.hyper-window-tiling.gnome;
          hyper-window-tiling-kde = final.hyper-window-tiling.kde;
          logitech-battery-gnome = final.callPackage ../../packages/logitech-battery.nix { };
          sushi-preview = final.callPackage ../../packages/sushi-preview.nix { };
          toshy = final.callPackage ../../packages/toshy.nix { };
          chezmoi-support = goWorkspacePackage {
            pname = "chezmoi-support";
            subPackages = [ "cmd/chezmoi-support" ];
            meta = {
              description = "Dotfiles helper used by chezmoi templates";
              mainProgram = "chezmoi-support";
            };
          };
          system-run-mcp = goWorkspacePackage {
            pname = "system-run-mcp";
            subPackages = [
              "cmd/system-run-mcp"
              "cmd/system-runner"
            ];
            meta = {
              description = "MCP server that runs commands through the local system runner";
              mainProgram = "system-run-mcp";
              platforms = final.lib.platforms.linux ++ final.lib.platforms.darwin;
            };
          };
          nd-tools = goWorkspacePackage {
            pname = "nd-tools";
            subPackages = [ "cmd/nd-tools" ];
            meta = {
              description = "Periodic updater for nix-dotfiles managed developer tools";
              mainProgram = "nd-tools";
              platforms = final.lib.platforms.linux ++ final.lib.platforms.darwin ++ final.lib.platforms.windows;
            };
          };
          ghidra-mcp-headless = final.eupkgs.ghidra-mcp-headless;
          lenovo-con-mode = goWorkspacePackage {
            pname = "lenovo-con-mode";
            subPackages = [ "cmd/lenovo-con-mode" ];
            meta = {
              description = "Toggle or set Lenovo Ideapad conservation mode";
              mainProgram = "lenovo-con-mode";
              platforms = final.lib.platforms.linux;
            };
          };
          lsp-diagnostic-filter = final.callPackage ../../packages/lsp-diagnostic-filter.nix { };
          macos-pointer = goWorkspacePackage {
            pname = "macos-pointer";
            subPackages = [ "cmd/macos-pointer" ];
            meta = {
              description = "macOS-style Linux pointer acceleration through evdev/uinput";
              mainProgram = "macos-pointer";
              platforms = final.lib.platforms.linux;
            };
          };
          zellij-theme-tools = goWorkspacePackage {
            pname = "zellij-theme-tools";
            subPackages = [ "cmd/zellij-theme-run" ];
            meta = {
              description = "Theme helpers for Zellij and Codex sessions";
              mainProgram = "zellij-theme-run";
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
