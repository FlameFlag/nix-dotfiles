{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib.options) mkOption;

  cfg = config.services.ghidra-mcp;
  types = lib.types;
  packageSet = pkgs.ghidra-mcp-headless;
  stateDir = cfg.stateDir;
  httpdExe = lib.getExe' packageSet.httpd "ghidra-mcp-httpd";
  bridgeExe = lib.getExe' packageSet.bridge "ghidra-mcp-bridge";
in
{
  options.services.ghidra-mcp = {
    enable = lib.options.mkEnableOption "Ghidra MCP headless HTTP backend plus streamable HTTP MCP bridge";

    user = mkOption {
      type = types.str;
      default = "nyx";
      description = "User that runs the Ghidra MCP services.";
    };

    group = mkOption {
      type = types.str;
      default = "users";
      description = "Group that owns the Ghidra MCP state directory.";
    };

    httpHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };

    httpPort = mkOption {
      type = types.port;
      default = 8089;
    };

    mcpHost = mkOption {
      type = types.str;
      default = "127.0.0.1";
    };

    mcpPort = mkOption {
      type = types.port;
      default = 8090;
    };

    stateDir = mkOption {
      type = types.path;
      default = "/home/${cfg.user}/.local/state/ghidra-mcp-headless";
    };

    allowScripts = mkOption {
      type = types.bool;
      default = true;
      description = "Enable Ghidra MCP script endpoints in the local headless backend.";
    };

    environmentFiles = mkOption {
      type = types.listOf types.path;
      default = [ ];
      example = [ "/run/keys/ghidra-mcp.env" ];
      description = ''
        Environment files to source before starting the Ghidra MCP systemd
        services. This is useful for values such as GHIDRA_MCP_AUTH_TOKEN
        without putting secrets into the Nix store.
      '';
    };

    extraEnvironment = mkOption {
      type = types.attrsOf types.str;
      default = { };
      description = "Extra environment variables passed to the Ghidra MCP systemd services.";
    };
  };

  config = lib.modules.mkIf cfg.enable {
    environment.systemPackages = [
      packageSet.ghidra
      packageSet.httpd
      packageSet.bridge
    ];

    systemd.tmpfiles.rules = [
      "d ${stateDir} 0755 ${cfg.user} ${cfg.group} - -"
    ];

    systemd.services.ghidra-mcp-httpd = {
      description = "Ghidra MCP headless HTTP backend";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];
      environment = cfg.extraEnvironment // {
        GHIDRA_MCP_BIND = cfg.httpHost;
        GHIDRA_MCP_PORT = toString cfg.httpPort;
        GHIDRA_MCP_ALLOW_SCRIPTS = if cfg.allowScripts then "1" else "0";
        GHIDRA_MCP_STATE = toString stateDir;
        JAVA_OPTS = "-Xmx4g -XX:+UseG1GC";
      };
      serviceConfig = {
        ExecStart = httpdExe;
        EnvironmentFile = cfg.environmentFiles;
        Group = cfg.group;
        Restart = "on-failure";
        User = cfg.user;
        WorkingDirectory = toString stateDir;
      };
    };

    systemd.services.ghidra-mcp-bridge = {
      description = "Ghidra MCP streamable HTTP bridge";
      wantedBy = [ "multi-user.target" ];
      after = [
        "network.target"
        "ghidra-mcp-httpd.service"
      ];
      requires = [ "ghidra-mcp-httpd.service" ];
      environment = cfg.extraEnvironment // {
        GHIDRA_MCP_BIND = cfg.httpHost;
        GHIDRA_MCP_PORT = toString cfg.httpPort;
        GHIDRA_MCP_URL = "http://${cfg.httpHost}:${toString cfg.httpPort}";
        GHIDRA_MCP_BRIDGE_HOST = cfg.mcpHost;
        GHIDRA_MCP_BRIDGE_PORT = toString cfg.mcpPort;
        GHIDRA_MCP_BRIDGE_TRANSPORT = "streamable-http";
        GHIDRA_MCP_STATE = toString stateDir;
      };
      serviceConfig = {
        ExecStart = bridgeExe;
        EnvironmentFile = cfg.environmentFiles;
        Group = cfg.group;
        Restart = "on-failure";
        User = cfg.user;
        WorkingDirectory = toString stateDir;
      };
    };
  };
}
