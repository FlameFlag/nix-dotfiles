{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.hm.firefox.enable = lib.mkEnableOption "Declerative Firefox";

  config = lib.mkIf config.hm.firefox.enable {
    programs.firefox = {
      enable = true;
      profiles.default = {
        isDefault = true;
        extensions.force = true;
        extensions.packages =
          builtins.attrValues {
            inherit (pkgs.nur.repos.rycee.firefox-addons)
              ublock-origin
              sponsorblock
              dearrow
              violentmonkey
              clearurls
              ;
          }
          ++ lib.optionals config.catppuccin.enable (
            builtins.attrValues {
              inherit (pkgs.nur.repos.rycee.firefox-addons) catppuccin-web-file-icons;
            }
          )
          ++ [
            (pkgs.fetchFirefoxAddon {
              name = "minimal-twitter";
              url = "https://addons.mozilla.org/firefox/downloads/latest/minimaltwitter/addon-6.3.0.xpi";
              sha256 = "sha256-h6r9hA2U2froAHU8x5hExwHgtU9010Cc/nHrLPW0kFo=";
            })
          ];
        settings = {
          "media.hardware-video-decoding.force-enabled" = true;
          "gfx.x11-egl.force-enabled" = true;
          "widget.dmabuf.force-enabled" = true;
        };
        search = {
          force = true;
          default = "google";
          privateDefault = "google";
          order = [
            "GitHub"
            "google"
            "Kagi"
            "Nix Packages"
            "youtube"
          ];
          engines = {
            GitHub = {
              urls = [
                {
                  template = "https://github.com/search";
                  params = [
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "https://github.com/favicon.ico";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = [ "@gh" ];
            };
            google.metaData.alias = "@g"; # builtin engines only support specifying one additional alias
            Kagi = {
              urls = [
                {
                  template = "https://kagi.com/search";
                  params = [
                    {
                      name = "q";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "https://assets.kagi.com/v2/apple-touch-icon.png";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = [ "@k" ];
            };
            "Nix Packages" = {
              urls = [
                {
                  template = "https://search.nixos.org/packages";
                  params = [
                    {
                      name = "channel";
                      value = "unstable";
                    }
                    {
                      name = "query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "${pkgs.nixos-icons}/share/icons/hicolor/scalable/apps/nix-snowflake.svg";
              definedAliases = [ "@np" ];
            };
            youtube = {
              urls = [
                {
                  template = "https://www.youtube.com/results";
                  params = [
                    {
                      name = "search_query";
                      value = "{searchTerms}";
                    }
                  ];
                }
              ];
              icon = "https://youtube.com/favicon.ico";
              updateInterval = 24 * 60 * 60 * 1000;
              definedAliases = [ "@yt" ];
            };
          };
        };
      };
      policies = {
        DisableTelemetry = true;
        OfferToSaveLogins = false;
        OfferToSaveLoginsDefault = false;
        PasswordManagerEnabled = false;
        NoDefaultBookmarks = true;
        DisableFirefoxAccounts = true;
        DisableFeedbackCommands = true;
        DisableFirefoxStudies = true;
        DisableMasterPasswordCreation = true;
        DisablePocket = true;
        DisableSetDesktopBackground = true;
      };
    };
  };
}
