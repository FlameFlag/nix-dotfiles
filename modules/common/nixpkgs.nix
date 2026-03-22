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
        yt-dlp = final.callPackage ../../pkgs/yt-dlp.nix { yt-dlp = final.unstable.yt-dlp; };
        yt-dlp-script = final.callPackage ../../pkgs/yt-dlp-script.nix { };
      })
    ];
  };
}
