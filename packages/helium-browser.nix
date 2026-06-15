{ callPackage }:

callPackage ./go-workspace-package.nix { } {
  pname = "helium-browser";
  subPackages = [ "cmd/helium-browser" ];

  meta = {
    description = "Install and configure Helium browser";
    mainProgram = "helium-browser";
  };
}
