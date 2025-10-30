{ inputs, ... }:
{
  nixpkgs = {
    config.allowUnfree = true;
    overlays = [
      inputs.nur.overlays.default
      inputs.helix.overlays.default
      inputs.nix4vscode.overlays.default
      (final: prev: {
        yt-dlp = final.callPackage ../../pkgs/yt-dlp.nix { };
        yt-dlp-script = final.callPackage ../../pkgs/yt-dlp-script.nix { };
      })
    ];
  };
}
