{
  imports = [
    ../hardware-configuration.nix
    ../networking.nix
    ../packages.nix
    ../programs.nix
    ../services.nix
    ../sound.nix
    ../users.nix
    ./boot.nix
    ./fonts.nix
    ./hardware.nix
    ./locale.nix
    ./nix-compat.nix
    ./system.nix
  ];
}
