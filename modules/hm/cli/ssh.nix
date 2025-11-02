{
  pkgs,
  lib,
  config,
  osConfig,
  ...
}:
let

  home = config.home.homeDirectory;
  sockPath =
    if pkgs.stdenvNoCC.hostPlatform.isDarwin then
      "Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
    else
      ".1password/agent.sock";
in
{
  options.hm.ssh.enable = lib.mkEnableOption "SSH";

  config = lib.mkIf config.hm.git.enable {
    home.sessionVariables = {
      SSH_AUTH_SOCK = "${home}/${sockPath}";
    };
    programs.ssh = {
      enable = true;
      package = pkgs.openssh_hpn;
      addKeysToAgent = "yes";
      extraConfig = ''
        Host *
          IdentityAgent "${home}/${sockPath}"

        Host github.com
          Hostname ssh.github.com
          Port 443
          User git
          IdentityFile ${osConfig.sops.secrets.github_ssh.path}
      '';
    };
  };
}
