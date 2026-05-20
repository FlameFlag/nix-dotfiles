{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (builtins) map;
  inherit (lib.attrsets)
    attrValues
    genAttrs
    genAttrs'
    nameValuePair
    ;
  inherit (lib.meta) getExe';
  inherit (lib.modules) mkIf mkMerge;
  inherit (lib.options) mkEnableOption;
  inherit (lib.gvariant)
    mkBoolean
    mkInt32
    mkString
    mkArray
    mkEmptyArray
    type
    ;

  workspaceNumbers = map toString (lib.lists.range 1 9);

  generateKeybindings =
    prefix: super: modifiers:
    let
      modifierStr = lib.strings.concatStrings modifiers;
    in
    genAttrs' workspaceNumbers (
      num: nameValuePair "${prefix}-${num}" (mkArray [ "${super}${modifierStr}${num}" ])
    );

  sleepTargets = [
    "systemd-suspend.service"
    "systemd-hibernate.service"
  ];

  gnomeShell = getExe' pkgs.gnome-shell "gnome-shell";
  pkill = getExe' pkgs.procps "pkill";
in
{
  options.nixOS.gnome.enable = mkEnableOption "GNOME";
  options.nixOS.dconf.enable = mkEnableOption "Dconf";

  config = mkMerge [
    (mkIf config.nixOS.gnome.enable {
      services = {
        displayManager.gdm.enable = true;
        desktopManager.gnome.enable = true;
      };
      environment.systemPackages = attrValues {
        inherit (pkgs) wl-clipboard;
        inherit (pkgs)
          apostrophe # Markdown Editor
          decibels # Audio Player
          gnome-obfuscate # Censor Private Info
          loupe # Image Viewer
          mousai # Shazam-like
          papers # PDF Viewer
          resources # Task Manager
          showtime # Video Player
          ;
      };
      environment.gnome.excludePackages = attrValues {
        inherit (pkgs)
          gnome-maps
          gnome-music
          gnome-tour
          gnome-weather
          epiphany # Browser
          geary # Email
          evince # Docs
          totem # Videos
          ;
      };
    })
    # Fix for GNOME suspend/resume issues with NVIDIA GPUs
    (mkIf config.nixOS.nvidia.enable {
      systemd.services = {
        gnome-suspend = {
          description = "Suspend gnome shell";
          before = sleepTargets ++ [
            "nvidia-suspend.service"
            "nvidia-hibernate.service"
          ];
          wantedBy = sleepTargets;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkill} -f -STOP ${gnomeShell}";
          };
        };
        gnome-resume = {
          description = "Resume gnome shell";
          after = sleepTargets ++ [
            "nvidia-resume.service"
          ];
          wantedBy = sleepTargets;
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${pkill} -f -CONT ${gnomeShell}";
          };
        };
      };
    })
    (mkIf config.nixOS.dconf.enable {
      environment.systemPackages = attrValues {
        inherit (pkgs.gnomeExtensions) appindicator clipboard-indicator pip-on-top;
      };
      programs.dconf.profiles.user.databases = [
        {
          lockAll = true; # Prevents overriding
          settings = {
            "org/gnome/desktop/interface" = {
              gtk-enable-primary-paste = mkBoolean false;
              enable-animations = mkBoolean false;
              clock-show-date = mkBoolean true;
              clock-show-seconds = mkBoolean true;
              clock-format = mkString "24h";
            };

            "org/gnome/desktop/wm/preferences" = {
              num-workspaces = mkInt32 9;
              button-layout = mkString "close,minimize,maximize:";
              resize-with-right-button = mkBoolean true;
            };

            /*
              For some reason, `switch-to-workplace` will also assign
              `switch-to-application`, which we do not want as it breaks
              everything, so we have to explicitly set it to nothing
            */
            "org/gnome/shell/keybindings" = genAttrs (map (n: "switch-to-application-${n}") workspaceNumbers) (
              _: mkEmptyArray type.string
            );

            "org/gnome/desktop/wm/keybindings" = {
              maximize = mkArray [ "<Super><Shift>Return" ];
              move-to-side-n = mkArray [ "<Super>w" ];
              move-to-side-s = mkArray [ "<Super>s" ];
              switch-applications = mkEmptyArray type.string;
              switch-windows = mkArray [
                "<Alt>Tab"
                "<Super>Tab"
              ];
            }
            // generateKeybindings "switch-to-workspace" "<Super>" [ ]
            // generateKeybindings "move-to-workspace" "<Super>" [ "<Shift>" ];

            "org/gnome/shell/app-switcher" = {
              current-workspace-only = mkBoolean false;
            };

            "org/gnome/shell" = {
              enabled-extensions = mkArray [
                "appindicatorsupport@rgcjonas.gmail.com"
                "clipboard-indicator@tudmotu.com"
                "pip-on-top@rafostar.github.com"
              ];
            };
          };
        }
      ];
    })
  ];
}
