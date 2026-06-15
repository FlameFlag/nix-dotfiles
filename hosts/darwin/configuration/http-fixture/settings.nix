{ config, lib }:
let
  configSource = ../../../../internal/httpfixture/fixtures/alt-tab.toml;
  parsedConfig = builtins.fromTOML (builtins.readFile configSource);
  upstreamDefault = parsedConfig.listen or "127.0.0.1:18081";
  fixtureHosts =
    if (parsedConfig.hosts or [ ]) != [ ] then
      parsedConfig.hosts
    else
      throw "http-fixture TOML must define at least one [[hosts]] entry";
  routes = lib.listToAttrs (
    map (host: {
      name = host.domain;
      value = {
        aliases = host.aliases or [ ];
        upstream = host.upstream or upstreamDefault;
        passThrough = host.pass_through or null;
        fixtureRoutes = parsedConfig.routes or [ ];
      };
    }) fixtureHosts
  );
  domains = lib.concatMap (domain: [ domain ] ++ (routes.${domain}.aliases or [ ])) (
    lib.attrNames routes
  );
in
rec {
  inherit
    configSource
    domains
    routes
    ;

  user = config.system.primaryUser;
  stateDir = "/etc/http-fixture";
  configFile = "${stateDir}/config.toml";
  cert = "${stateDir}/cert.pem";
  key = "${stateDir}/key.pem";
  sanFile = "${stateDir}/domains.txt";
  sanList = lib.concatMapStringsSep "," (domain: "DNS:${domain}") domains;

  caddyfile = "/etc/caddy/http-fixture.caddyfile";
  caddyfileTemplate = "/etc/caddy/http-fixture.caddyfile.template";
  fixtureLog = "/Users/${user}/Library/Logs/http-fixture.log";
  proxyLog = "/var/log/http-fixture-proxy.log";

  keepAliveUnlessStopped = {
    Crashed = true;
    SuccessfulExit = false;
  };

  hostAliases = {
    "127.0.0.1" = domains;
    "::1" = domains;
  };

  hostsToLines =
    hosts:
    lib.concatMapStringsSep "\n" (
      ip: lib.concatMapStringsSep "\n" (host: "${ip} ${host}") hosts.${ip}
    ) (lib.attrNames hosts);
}
