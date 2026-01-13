{
  lib,
  inputs,
  config,
  ...
}:
{
  config = lib.mkMerge [
    ({
      nix.extraOptions = ''
        !include ${config.sops.secrets.github-token.path}
      '';
      sops.secrets.github-token = {
        mode = "0440";
        group = if config.nixpkgs.hostPlatform.isDarwin then "wheel" else "root";
      };
    })
    ({
      nix.settings = {
        trusted-users = [
          "flame"
          "nyx"
        ];
        experimental-features = "nix-command flakes";
        substituters = [
          "https://devenv.cachix.org"
          "https://nix-community.cachix.org"
          "https://helix.cachix.org"
        ];
        trusted-public-keys = [
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
          "helix.cachix.org-1:ejp9KQpR1FBI2onstMQ34yogDm4OgU2ru6lIwPvuCVs="
        ];
      }
      // lib.optionalAttrs config.nixpkgs.hostPlatform.isLinux { flake-registry = ""; };
    })
    ({
      nix = {
        channel.enable = false;
        # Opinionated: make flake registry and nix path match flake inputs
        registry = lib.mapAttrs (_: flake: { inherit flake; }) (
          # Flake Inputs
          lib.filterAttrs (_: lib.isType "flake") inputs
        );
        nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") (
          # Flake Inputs
          lib.filterAttrs (_: lib.isType "flake") inputs
        );
      };
    })
  ];
}
