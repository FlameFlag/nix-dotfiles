{
  inputs,
  config,
  lib,
  ...
}:
let
  inherit (config.nixpkgs.hostPlatform) system isLinux;
in
{
  nixpkgs = {
    config = {
      allowUnfree = true;
    }
    // lib.optionalAttrs isLinux { cudaSupport = true; };
    overlays = [
      inputs.nur.overlays.default
      (final: prev: {
        yt-dlp = final.callPackage ../../pkgs/yt-dlp.nix { };
        yt-dlp-script = final.callPackage ../../pkgs/yt-dlp-script.nix { };
      })
      (final: prev: {
        lix =
          (inputs.lix.packages.${system}.default.override { aws-sdk-cpp = null; }).overrideAttrs
            (args: {
              postPatch = (args.postPatch or "") + ''
                substituteInPlace lix/libmain/shared.cc \
                  --replace-fail "(Lix, like Nix)" "(Lix, like Nix but better)"        
              '';
              # This assumes that the tests will never break
              doCheck = false;
            });
      })
    ];
  };
}
