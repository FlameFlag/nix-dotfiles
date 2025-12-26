{ inputs, ... }:
{
  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      (final: prev: {
        unstable = import inputs.nixpkgs-unstable {
          inherit (prev) system config;
        };
      })
      inputs.nur.overlays.default
      inputs.nix4vscode.overlays.default
      (final: prev: {
        yt-dlp = final.callPackage ../../pkgs/yt-dlp.nix { };
        yt-dlp-script = final.callPackage ../../pkgs/yt-dlp-script.nix { };
      })
    ];
  };
}
