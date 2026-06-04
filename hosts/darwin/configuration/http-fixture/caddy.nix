{ config, lib, ... }:
let
  settings = import ./settings.nix { inherit config lib; };
  rendering = import ./rendering.nix { inherit lib settings; };
in
{
  environment.etc."http-fixture/config.toml".source = settings.configSource;

  environment.etc."caddy/http-fixture.caddyfile.template".text = ''
    {
    	admin off
    	auto_https off
    }

    ${lib.trim rendering.passThroughSnippets}

    ${lib.trim rendering.sites}
  '';

  system.activationScripts.postActivation.text = lib.mkAfter ''
    install -d -m 0755 -o root -g wheel /etc/caddy
    caddy_rendered="$(mktemp)"
    cp ${settings.caddyfileTemplate} "$caddy_rendered"
    ${rendering.renderPassThroughUpstreams}
    install -m 0644 -o root -g wheel "$caddy_rendered" ${settings.caddyfile}
    rm -f "$caddy_rendered"

    launchctl bootout system/org.nixos.http-fixture-lab 2>/dev/null || true
    launchctl bootout system/org.nixos.local-fixture-proxy 2>/dev/null || true
    launchctl kickstart -k system/org.nixos.http-fixture 2>/dev/null || true
    launchctl kickstart -k system/org.nixos.http-fixture-proxy 2>/dev/null || true
  '';
}
