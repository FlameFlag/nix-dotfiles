{ pkgs }:

let
  ghidraMcp = pkgs.ghidra-mcp-headless;
in
pkgs.buildEnv {
  name = "nix-dotfiles-linux-toolbox-profile";
  paths = [
    ghidraMcp.ghidra
    ghidraMcp.httpd
    ghidraMcp.bridge
  ];

  pathsToLink = [
    "/bin"
    "/share"
  ];

  meta = {
    description = "Container-exported Linux tools that are awkward outside Nix";
    platforms = pkgs.lib.platforms.linux;
  };
}
