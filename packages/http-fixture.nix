{ callPackage }:

callPackage ./go-workspace-package.nix { } {
  pname = "http-fixture";
  subPackages = [ "cmd/http-fixture" ];

  meta = {
    description = "Small local fixture HTTP server";
    mainProgram = "http-fixture";
  };
}
