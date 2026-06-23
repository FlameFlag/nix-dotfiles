{
  callPackage,
  lib,
  pkgs,
}:

let
  runtimeInputs = with pkgs; [
    coreutils
    findutils
    git
    gnugrep
    gnused
    ansible
    nix
  ];
in
callPackage ./go-workspace-package.nix { } {
  pname = "immutable-activate";
  subPackages = [ "cmd/immutable-activate" ];

  ldflags = [
    "-X"
    "main.runtimePath=${lib.makeBinPath runtimeInputs}"
    "-X"
    "main.distroboxManifest=${placeholder "out"}/share/nix-dotfiles/immutable/distrobox.ini"
  ];

  postInstall = ''
    install -Dm644 ${../internal/immutableactivate/container/distrobox.ini} "$out/share/nix-dotfiles/immutable/distrobox.ini"
  '';

  meta = {
    description = "Activate the nix-dotfiles immutable Linux user profile";
    mainProgram = "immutable-activate";
    platforms = lib.platforms.linux;
  };
}
