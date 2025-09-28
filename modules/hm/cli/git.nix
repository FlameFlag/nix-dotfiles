{
  pkgs,
  lib,
  config,
  ...
}:
let
  userName = "FlameFlag";
  userEmail = "57304299+${userName}@users.noreply.github.com";
  key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPsZFHUhLSPiz0EF1Q59jzu7IS7qdn3MSEImztN4KgmN";
  format = "ssh";
in
{
  options.hm.git.enable = lib.mkEnableOption "Git";

  config = lib.mkIf config.hm.git.enable {
    home.file.".gitconfig".source =
      config.lib.file.mkOutOfStoreSymlink "${config.xdg.configHome}/git/config";
    home.file.".ssh/allowed_signers".text = ''
      ${userEmail} ${key}
    '';

    home.packages = builtins.attrValues { inherit (pkgs) watchman; };

    programs = {
      gitui.enable = true;
      gh.enable = true;
      gh.settings.git_protocol = format;
      git = {
        enable = true;
        ignores = [
          ".DS_Store"
          "Thumbs.db"
          "*.DS_Store"
          "*.swp"
        ];
        inherit userName userEmail;
        signing = {
          inherit key format;
          signByDefault = true;
          signer =
            if pkgs.stdenvNoCC.hostPlatform.isLinux then
              (lib.getExe' pkgs._1password-gui "op-ssh-sign")
            else
              "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
        };
      };
      vscode.profiles.default.userSettings."git.enableCommitSigning" =
        if config.programs.git.signing.signByDefault then true else false;
      jujutsu = {
        enable = true;
        settings = {
          fsmonitor.backend = "watchman";
          fsmonitor.watchman.register-snapshot-trigger = true;
          user.email = userEmail;
          user.name = userName;
          ui = {
            paginate = "auto";
            merge-editor = "vscode";
            diff-formatter = ":git";
            default-command = "log";
          };
          git = {
            sign-on-push = true;
            auto-local-bookmark = false;
          };
          aliases = {
            d = [ "describe" ];
            p = [ "git push" ];
            e = [ "edit" ];
            n = [ "new" ];
          };
          signing = {
            behavior = "own";
            backend = "ssh";
            inherit key;
            backends.ssh.program =
              if pkgs.stdenvNoCC.hostPlatform.isLinux then
                (lib.getExe' pkgs._1password-gui "op-ssh-sign")
              else
                "/Applications/1Password.app/Contents/MacOS/op-ssh-sign";
            backends.ssh.allowed-signers = "${config.home.homeDirectory}/.ssh/allowed_signers";
          };
          templates = {
            git_push_bookmark = ''"${lib.strings.toLower userName}/push-" ++ change_id.short()'';
            duplicate_description = "concat(description, \"\\n(cherry picked from commit \", commit_id, \")\")";
          };
        };
      };
    };
  };
}
