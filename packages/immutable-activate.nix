{
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
    nix
    scaffold
  ];
in
pkgs.stdenvNoCC.mkDerivation {
  pname = "immutable-activate";
  version = "0.1.0";

  src = ./immutable-activate.sh;

  dontUnpack = true;

  nativeBuildInputs = with pkgs; [
    bash
    shellcheck-minimal
    shfmt
  ];

  installPhase = ''
    runHook preInstall

    install -Dm755 "$src" "$out/bin/immutable-activate"
    substituteInPlace "$out/bin/immutable-activate" \
      --replace-fail '#!/bin/bash' '#!${lib.getExe pkgs.bash}' \
      --replace-fail '@runtimePath@' '${lib.makeBinPath runtimeInputs}'

    runHook postInstall
  '';

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    bash -n "$src"
    shfmt -d -i 2 -bn "$src"
    shellcheck "$src"

    runHook postCheck
  '';

  meta = {
    description = "Activate the nix-dotfiles immutable Linux user profile";
    mainProgram = "immutable-activate";
    platforms = lib.platforms.linux;
  };
}
