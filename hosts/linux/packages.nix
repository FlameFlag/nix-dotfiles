{ lib, pkgs, ... }:
{
  environment.systemPackages = (
    lib.attrsets.attrValues {
      inherit (pkgs) bootstrap;
      inherit (pkgs) telegram-desktop;
      inherit (pkgs.unstable) jq;
    }
  );

  system.activationScripts.removeBootstrapSelfInstall.text = ''
    bootstrap_link=/home/nyx/.local/bin/bootstrap
    if [ -L "$bootstrap_link" ]; then
      bootstrap_target="$(readlink -f "$bootstrap_link" || true)"
      case "$bootstrap_target" in
        /home/nyx/.local/opt/bootstrap/*|/home/nyx/.local/opt/nix-dotfiles-bootstrap/*)
          rm -f "$bootstrap_link"
          ;;
      esac
    fi
  '';
}
