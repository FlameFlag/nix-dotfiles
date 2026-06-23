{
  config,
  lib,
  pkgs,
  ...
}:
let
  paidFonts = (pkgs.callPackage ../../packages/paid-fonts/build-font.nix { }).packages;
in
{
  services = {
    kmscon = {
      enable = true;
      hwRender = true;
      useXkbConfig = true;
      extraOptions = "--term xterm-256color";
      fonts = lib.mkIf config.flame.fonts.paid.enable [
        {
          name = "TX-02 Nerd Font";
          package = paidFonts.tx-02;
        }
      ];
    };

    libinput.enable = true;
    openssh.enable = true;
    xserver.xkb.layout = "us";
  };

  systemd.user.services.nd-tools-update = {
    description = "Run periodic nix-dotfiles tool updaters";
    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.findutils
    ];
    script = ''
      exec "$HOME/.local/bin/nd-tools" update
    '';
    serviceConfig = {
      Type = "oneshot";
      CapabilityBoundingSet = "";
      LockPersonality = true;
      NoNewPrivileges = true;
      PrivateDevices = true;
      PrivateTmp = true;
      ProtectClock = true;
      ProtectControlGroups = true;
      ProtectHome = false;
      ProtectHostname = true;
      ProtectKernelLogs = true;
      ProtectKernelModules = true;
      ProtectKernelTunables = true;
      ProtectSystem = "full";
      RestrictAddressFamilies = [
        "AF_UNIX"
        "AF_INET"
        "AF_INET6"
      ];
      RestrictRealtime = true;
      RestrictSUIDSGID = true;
      SystemCallArchitectures = "native";
      UMask = "022";
    };
  };

  systemd.user.timers.nd-tools-update = {
    description = "Run periodic nix-dotfiles tool updaters every six hours";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10m";
      OnUnitActiveSec = "6h";
      Persistent = true;
    };
  };
}
