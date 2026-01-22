{
  pkgs,
  lib,
  config,
  ...
}:
let
  inherit (lib.gvariant)
    mkBoolean
    mkInt32
    mkString
    mkArray
    mkEmptyArray
    type
    ;

  generateKeybindings =
    prefix: super: modifiers: range:
    builtins.listToAttrs (
      builtins.genList (
        x:
        let
          num = toString (x + 1);
          modifierStr = builtins.concatStringsSep "" modifiers;
        in
        {
          name = "${prefix}-${num}";
          value = mkArray [ "${super}${modifierStr}${num}" ];
        }
      ) range
    );
in
{
  options.nixOS.gnome.enable = lib.mkEnableOption "GNOME";
  options.nixOS.dconf.enable = lib.mkEnableOption "Dconf";

  config = lib.mkMerge [
    (lib.mkIf config.nixOS.gnome.enable {
      services = {
        displayManager.gdm.enable = true;
        desktopManager.gnome.enable = true;
      };
      environment.systemPackages = builtins.attrValues {
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
      environment.gnome.excludePackages = builtins.attrValues {
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
    (lib.mkIf config.nixOS.nvidia.enable {
      systemd.services = {
        gnome-suspend = {
          description = "Suspend gnome shell";
          before = [
            "systemd-suspend.service"
            "systemd-hibernate.service"
            "nvidia-suspend.service"
            "nvidia-hibernate.service"
          ];
          wantedBy = [
            "systemd-suspend.service"
            "systemd-hibernate.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe' pkgs.procps "pkill"} -f -STOP ${lib.getExe' pkgs.gnome-shell "gnome-shell"}";
          };
        };
        gnome-resume = {
          description = "Resume gnome shell";
          after = [
            "systemd-suspend.service"
            "systemd-hibernate.service"
            "nvidia-resume.service"
          ];
          wantedBy = [
            "systemd-suspend.service"
            "systemd-hibernate.service"
          ];
          serviceConfig = {
            Type = "oneshot";
            ExecStart = "${lib.getExe' pkgs.procps "pkill"} -f -CONT ${lib.getExe' pkgs.gnome-shell "gnome-shell"}";
          };
        };
      };
    })
    (lib.mkIf config.nixOS.dconf.enable {
      environment.systemPackages = builtins.attrValues {
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
            "org/gnome/shell/keybindings" = lib.genAttrs (map (n: "switch-to-application-${toString n}") (
              lib.range 1 9
            )) (_: mkEmptyArray type.string);

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
            // (generateKeybindings "switch-to-workspace" "<Super>" [ ] 9)
            // (generateKeybindings "move-to-workspace" "<Super>" [ "<Shift>" ] 9);

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
