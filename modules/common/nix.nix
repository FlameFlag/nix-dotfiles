{
  lib,
  inputs,
  config,
  ...
}:
let
  flakeInputs = lib.filterAttrs (_: lib.isType "flake") inputs;
in
{
  config = lib.mkMerge [
    ({
      nix.extraOptions = ''
        !include ${config.sops.secrets.github-token.path}
      '';
      sops.secrets.github-token = {
        mode = lib.mkDefault "0440";
        group = lib.mkDefault (if config.nixpkgs.hostPlatform.isDarwin then "staff" else "root");
      };
    })
    ({
      nix = {
        distributedBuilds = true;
        buildMachines = [
          {
            hostName = "naxe";
            protocol = "ssh-ng";
            system = "x86_64-linux";
            sshUser = "naxecode";
            sshKey = "/etc/nix/builder_ed25519";
            maxJobs = 4;
            speedFactor = 1;
            supportedFeatures = [
              "big-parallel"
              "benchmark"
              "nixos-test"
            ];
            publicHostKey = "c3NoLWVkMjU1MTkgQUFBQUMzTnphQzFsWkRJMU5URTVBQUFBSUdKbTZHa3ltRTF5bDF1eUhvNTFqSGVkckRVdHVGMGZNSThST2FOdUdnZFM=";
          }
        ];

        settings = {
          trusted-users = [
            "flame"
            "nyx"
          ];
          experimental-features = "nix-command flakes";
          builders-use-substitutes = true;
          keep-outputs = true;
          substituters = [
            "https://devenv.cachix.org"
            "https://nix-community.cachix.org"
            "https://cache.flox.dev"
          ];
          trusted-public-keys = [
            "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw="
            "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
            "flox-cache-public-1:7F4OyH7ZCnFhcze3fJdfyXYLQw/aV7GEed86nQ7IsOs="
          ];
          extra-sandbox-paths = [
            "/nix/var/cache/ccache"
            "/nix/var/cache/sccache"
          ];
        }
        // lib.optionalAttrs config.nixpkgs.hostPlatform.isLinux { flake-registry = ""; };
      };
    })
    ({
      system.activationScripts.postActivation.text = ''
        install -d -m 0770 -o root -g nixbld /nix/var/cache/ccache
        install -d -m 0770 -o root -g nixbld /nix/var/cache/sccache
      '';
    })
    ({
      nix = {
        channel.enable = false;
        # Opinionated: make flake registry and nix path match flake inputs
        registry = lib.mapAttrs (_: flake: { inherit flake; }) flakeInputs;
        nixPath = lib.mapAttrsToList (n: _: "${n}=flake:${n}") flakeInputs;
      };
    })
  ];
}
