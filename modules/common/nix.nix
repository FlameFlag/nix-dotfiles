{
  lib,
  inputs,
  config,
  ...
}:
{
  imports = [ inputs.lix-module.nixosModules.lixFromNixpkgs ];

  config = lib.mkMerge [
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
        ];
        trusted-public-keys = [
          "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
          "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        ];
      }
      // lib.optionalAttrs config.nixpkgs.hostPlatform.isLinux { flake-registry = ""; };
    })
    ({
      nix.buildMachines = lib.optionals config.nixpkgs.hostPlatform.isDarwin [
        {
          hostName = "lenovo-legion.local";
          protocol = "ssh-ng";
          publicHostKey = "IyBsZW5vdm8tbGVnaW9uLmxvY2FsOjIyIFNTSC0yLjAtT3BlblNTSF8xMC4wCmxlbm92by1sZWdpb24ubG9jYWwgc3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUNmL2hGNGIvWUdQQVArcFQrS1lhNWk3eUlCRHRsL2M4T2I4TTdrK3BxMHAK";
          sshKey = "/run/secrets/lenovo_legion_5_15arh05h_ssh";
          sshUser = "nyx";
          supportedFeatures = [
            "nixos-test"
            "big-parallel"
            "benchmark"
          ];
          systems = [ "x86_64-linux" ];
        }
      ];
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
        distributedBuilds = true;
      };
    })
  ];
}
