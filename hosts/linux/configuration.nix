{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./home.nix
    ./networking.nix
    ./packages.nix
    ./programs.nix
    ./services.nix
    ./sound.nix
    ./systemd.nix
    ./users.nix
    ./kanata.nix

    ../../shared/packages.nix
  ];

  environment = {
    # Add inputs to legacy (nix2) channels, making legacy nix commands consistent
    etc = lib.mapAttrs' (name: value: {
      name = "nix/path/${name}";
      value.source = value.flake;
    }) config.nix.registry;
  };

  # Keyboard layout
  i18n = {
    defaultLocale = "en_US.UTF-8";
    extraLocaleSettings = {
      LC_ADDRESS = "en_US.UTF-8";
      LC_IDENTIFICATION = "en_US.UTF-8";
      LC_MEASUREMENT = "en_US.UTF-8";
      LC_MONETARY = "en_US.UTF-8";
      LC_NAME = "en_US.UTF-8";
      LC_NUMERIC = "en_US.UTF-8";
      LC_PAPER = "en_US.UTF-8";
      LC_TELEPHONE = "en_US.UTF-8";
      LC_TIME = "en_US.UTF-8";
    };
  };

  hardware = {
    bluetooth.enable = true;
    bluetooth.powerOnBoot = true;
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  time.timeZone = "Europe/Sofia";

  fonts = {
    fontconfig = {
      defaultFonts = {
        monospace = [ "Monaspice Kr Nerd Font" ];
        sansSerif = [ "Noto Nerd Font" ];
        serif = [ "Noto Nerd Font" ];
        emoji = [ "Twitter Color Emoji" ];
      };
    };
    packages = builtins.attrValues {
      Ubuntu = pkgs.nerd-fonts.ubuntu;
      UbuntuMono = pkgs.nerd-fonts.ubuntu-mono;
      UbuntuSans = pkgs.nerd-fonts.ubuntu-sans;
      FiraCode = pkgs.nerd-fonts.fira-code;
      Monaspace = pkgs.nerd-fonts.monaspace;
      Noto = pkgs.nerd-fonts.noto;

      inherit (pkgs)
        noto-fonts-cjk-sans
        noto-fonts-emoji
        twemoji-color-font
        ;
    };
  };

  # https://wiki.nixos.org/wiki/FAQ#When_do_I_update_stateVersion
  system.stateVersion = "25.05";
}
