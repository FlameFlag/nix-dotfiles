{
  pkgs,
  lib,
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./networking.nix
    ./packages.nix
    ./programs.nix
    ./services.nix
    ./sound.nix
    ./users.nix
  ];

  environment = {
    # Add inputs to legacy (nix2) channels, making legacy nix commands consistent
    etc = lib.mapAttrs' (
      name: value: lib.nameValuePair "nix/path/${name}" { source = value.flake; }
    ) config.nix.registry;
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
  boot.kernelPackages = pkgs.linuxPackages_latest;

  hardware.nvidia.prime = {
    reverseSync.enable = true;
    amdgpuBusId = "PCI:6:0:0";
    nvidiaBusId = "PCI:1:0:0";
  };

  time.timeZone = "Europe/Sofia";

  fonts = {
    fontconfig = {
      defaultFonts = {
        monospace = [ "TX-02 Nerd Font" ];
      };
    };
    packages = lib.optionals config.flame.fonts.paid.enable (
      let
        paidFonts = (pkgs.callPackage ../../pkgs/paid-fonts/build-font.nix { }).packages;
      in
      builtins.attrValues paidFonts
    );
  };

  # https://wiki.nixos.org/wiki/FAQ#When_do_I_update_stateVersion
  system.stateVersion = "25.11";
}
