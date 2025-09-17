{
  inputs,
  pkgs,
  lib,
  config,
  osConfig,
  ...
}:
{
  imports = [
    ./keybindings.nix
    ./settings.nix
  ];

  options.hm.yazi.enable = lib.mkEnableOption "Yazi";

  config = lib.mkIf config.hm.yazi.enable {
    xdg.configFile = {
      "yazi/plugins/smart-paste.yazi/main.lua".text = builtins.readFile ./plugins/smart-paste.lua;
    };
    home.packages = builtins.attrValues { inherit (pkgs) mediainfo exiftool clipboard-jh; };
    programs.yazi = {
      enable = true;
      package = inputs.yazi.packages.${osConfig.nixpkgs.hostPlatform.system}.default.overrideAttrs ({
        doCheck = false;
      });
      plugins =
        let
          pluginsRepo = pkgs.fetchFromGitHub {
            owner = "yazi-rs";
            repo = "plugins";
            rev = "d7588f6d29b5998733d5a71ec312c7248ba14555";
            hash = "sha256-9+58QhdM4HVOAfEC224TrPEx1N7F2VLGMxKVLAM4nJw=";
          };
        in
        {
          diff = "${pluginsRepo}/diff.yazi";
          full-border = "${pluginsRepo}/full-border.yazi";
          hide-preview = "${pluginsRepo}/hide-preview.yazi";
          max-preview = "${pluginsRepo}/max-preview.yazi";
          smart-enter = "${pluginsRepo}/smart-enter.yazi";
          system-clipboard = pkgs.applyPatches {
            src = pkgs.fetchFromGitHub {
              owner = "orhnk";
              repo = "system-clipboard.yazi";
              rev = "4f6942dd5f0e143586ab347d82dfd6c1f7f9c894";
              hash = "sha256-M7zKUlLcQA3ihpCAZyOkAy/SzLu31eqHGLkCSQPX1dY=";
            };
            patches = [
              (pkgs.writeText "system-clipboard-fix.patch" ''
                diff --git a/main.lua b/main.lua
                index 0e77f6a7bd..666604668d 100644
                --- a/main.lua
                +++ b/main.lua
                @@ -13,7 +13,7 @@
                 
                 return {
                 	entry = function()
                -		ya.manager_emit("escape", { visual = true })
                +		ya.mgr_emit("escape", { visual = true })
                 
                 		local urls = selected_or_hovered()
              '')
            ];
          };
        }
        // lib.optionalAttrs config.programs.git.enable { git = "${pluginsRepo}/git.yazi"; }
        // lib.optionalAttrs config.programs.starship.enable {
          starship = pkgs.fetchFromGitHub {
            owner = "Rolv-Apneseth";
            repo = "starship.yazi";
            rev = "a63550b2f91f0553cc545fd8081a03810bc41bc0";
            hash = "sha256-PYeR6fiWDbUMpJbTFSkM57FzmCbsB4W4IXXe25wLncg=";
          };
        };
      initLua =
        ''require('full-border'):setup()''
        + lib.optionalString config.programs.git.enable ''require("git"):setup()''
        + lib.optionalString config.programs.starship.enable ''require("starship"):setup()'';
    };
  };
}
