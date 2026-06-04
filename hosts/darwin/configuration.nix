{
  inputs,
  pkgs,
  config,
  lib,
  ...
}:
let
  user = config.system.primaryUser;
  keepAliveUnlessStopped = {
    Crashed = true;
    SuccessfulExit = false;
  };
  httpFixtureConfigSource = ../../fixtures/alt-tab.toml;
  httpFixtureConfig = builtins.fromTOML (builtins.readFile httpFixtureConfigSource);
  httpFixtureHosts =
    if (httpFixtureConfig.hosts or [ ]) != [ ] then
      httpFixtureConfig.hosts
    else
      throw "http-fixture TOML must define at least one [[hosts]] entry";
  httpFixtureUpstream = httpFixtureConfig.listen or "127.0.0.1:18081";
  httpFixtureLog = "/Users/${user}/Library/Logs/http-fixture.log";
  httpFixtureProxyLog = "/var/log/http-fixture-proxy.log";
  httpFixtureStateDir = "/etc/http-fixture";
  httpFixtureConfigFile = "${httpFixtureStateDir}/config.toml";
  httpFixtureCert = "${httpFixtureStateDir}/cert.pem";
  httpFixtureKey = "${httpFixtureStateDir}/key.pem";
  httpFixtureSanFile = "${httpFixtureStateDir}/domains.txt";
  httpFixtureCaddyfile = "/etc/caddy/http-fixture.caddyfile";
  httpFixtureCaddyfileTemplate = "/etc/caddy/http-fixture.caddyfile.template";
  openssl = lib.meta.getExe pkgs.openssl;

  localHttpFixtures = lib.listToAttrs (
    map (host: {
      name = host.domain;
      value = {
        aliases = host.aliases or [ ];
        upstream = host.upstream or httpFixtureUpstream;
        passThrough = host.pass_through or null;
      };
    }) httpFixtureHosts
  );

  httpFixtureDomains = lib.concatMap (
    domain: [ domain ] ++ (localHttpFixtures.${domain}.aliases or [ ])
  ) (lib.attrNames localHttpFixtures);
  httpFixtureSanList = lib.concatMapStringsSep "," (domain: "DNS:${domain}") httpFixtureDomains;

  localHostAliases = {
    "127.0.0.1" = httpFixtureDomains;
    "::1" = httpFixtureDomains;
  };

  hostsToLines =
    hosts:
    lib.concatMapStringsSep "\n" (
      ip: lib.concatMapStringsSep "\n" (host: "${ip} ${host}") hosts.${ip}
    ) (lib.attrNames hosts);

  caddySnippetName =
    domain: "http_fixture_${lib.replaceStrings [ "." "-" ] [ "_" "_" ] domain}_pass_through";
  caddyUpstreamsPlaceholder =
    domain: "__HTTP_FIXTURE_UPSTREAMS_${lib.replaceStrings [ "." "-" ] [ "_" "_" ] domain}__";

  caddyPassThroughSnippet =
    domain:
    let
      route = localHttpFixtures.${domain};
      passThrough = route.passThrough;
      realHost = passThrough.host or domain;
      scheme = passThrough.scheme or "https";
      port = passThrough.port or (if scheme == "https" then 443 else 80);
      upstreams =
        if (passThrough.upstreams or [ ]) != [ ] then
          passThrough.upstreams
        else if passThrough ? upstream then
          [ passThrough.upstream ]
        else
          [ ];
      upstreamText =
        if upstreams != [ ] then lib.concatStringsSep " " upstreams else caddyUpstreamsPlaceholder domain;
      tlsConfig = lib.optionalString (scheme == "https") ''
        			tls
        			tls_server_name ${realHost}
      '';
    in
    lib.optionalString (passThrough != null) ''
      (${caddySnippetName domain}) {
      	reverse_proxy ${upstreamText} {
      		header_up Host ${realHost}
      		transport http {
      ${tlsConfig}
      		}
      	}
      }
    '';

  caddyPassThroughHandles =
    domain:
    let
      route = localHttpFixtures.${domain};
      passThrough = route.passThrough;
      snippetName = caddySnippetName domain;
      exactPaths = passThrough.paths or [ ];
      pathPrefixes = passThrough.path_prefixes or [ ];
      websitePrefix = passThrough.website_prefix or null;
      exactPathHandles = lib.concatMapStringsSep "\n" (path: ''
        	handle ${path} {
        		import ${snippetName}
        	}
      '') exactPaths;
      pathPrefixHandles = lib.concatMapStringsSep "\n" (pathPrefix: ''
        	handle ${pathPrefix}* {
        		import ${snippetName}
        	}
      '') pathPrefixes;
      websiteHandles = lib.optionalString (websitePrefix != null) ''
        	handle ${websitePrefix} {
        		redir * ${websitePrefix}/ 308
        	}

        	handle_path ${websitePrefix}/* {
        		import ${snippetName}
        	}
      '';
    in
    lib.optionalString (passThrough != null) ''
      ${lib.trim exactPathHandles}

      ${lib.trim pathPrefixHandles}

      ${lib.trim websiteHandles}
    '';

  caddySiteBlock =
    domain:
    let
      route = localHttpFixtures.${domain};
      names = [ domain ] ++ (route.aliases or [ ]);
    in
    ''
      https://${lib.concatStringsSep ", https://" names} {
      	bind 127.0.0.1 ::1
      	tls ${httpFixtureCert} ${httpFixtureKey}

      	route {
      ${caddyPassThroughHandles domain}

      		handle {
      			reverse_proxy ${route.upstream}
      		}
      	}
      }
    '';

  caddyPassThroughSnippets = lib.concatMapStringsSep "\n" caddyPassThroughSnippet (
    lib.attrNames localHttpFixtures
  );
  caddySites = lib.concatMapStringsSep "\n" caddySiteBlock (lib.attrNames localHttpFixtures);
  caddyRenderPassThroughUpstreams = lib.concatMapStringsSep "\n" (
    domain:
    let
      route = localHttpFixtures.${domain};
      passThrough = route.passThrough;
      realHost = passThrough.host or domain;
      scheme = passThrough.scheme or "https";
      resolvers = passThrough.resolvers or [ ];
      placeholder = caddyUpstreamsPlaceholder domain;
    in
    lib.optionalString
      (passThrough != null && !(passThrough ? upstream) && (passThrough.upstreams or [ ]) == [ ])
      ''
        upstreams="$(
          for resolver in ${lib.escapeShellArgs resolvers}; do
            resolver_host="''${resolver%:*}"
            /usr/bin/dig +short A "@$resolver_host" ${lib.escapeShellArg realHost} \
              | /usr/bin/awk '/^[0-9.]+$/ { print "${scheme}://"$0 }'
          done | /usr/bin/awk '!seen[$0]++'
        )"
        if [ -z "$upstreams" ]; then
          echo "failed to resolve pass-through upstream for ${realHost}" >&2
          exit 1
        fi
        upstreams_line="$(printf '%s\n' "$upstreams" | /usr/bin/tr '\n' ' ')"
        PLACEHOLDER=${lib.escapeShellArg placeholder} UPSTREAMS="$upstreams_line" \
          /usr/bin/perl -0pi -e 's/\Q$ENV{PLACEHOLDER}\E/$ENV{UPSTREAMS}/g' "$caddy_rendered"
      ''
  ) (lib.attrNames localHttpFixtures);
in
{
  imports = [ inputs.sops-nix.darwinModules.sops ];

  system.primaryUser = "flame";

  nixpkgs.hostPlatform.system = "aarch64-darwin";

  users.users.${config.system.primaryUser} = {
    name = "${config.system.primaryUser}";
    home = "/Users/${config.system.primaryUser}";
    shell = pkgs.unstable.zsh;
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAc3DwiG6OJVICR7FQQE+I9R2447GFLrIRyF9+xP6aM5 nyx@lenovo-legion"
    ];
  };

  services.openssh.enable = true;

  services.tailscale.enable = true;
  services.tailscale.package = pkgs.unstable.tailscale;

  environment.systemPackages = [
    pkgs.caddy
    pkgs.http-fixture
  ];

  environment.etc.hosts = {
    knownSha256Hashes = [
      "c7dd0e2ed261ce76d76f852596c5b54026b9a894fa481381ffd399b556c0e2da"
      "a4136e5c03c32d6e75aa6f26777e9e7d656d0412de3b0475a639b0bb1cf0aaf1"
      "3028877711bcae3a0ec29836415c7afdb9060479c27c550c2c8730baf8ea42e5"
      "4f4b6f0767b1031814d148ece9ee7f4174bc9eaeeec28aead99ac8d35d6b02ba"
    ];
    text = ''
      ##
      # Host Database
      #
      # localhost is used to configure the loopback interface
      # when the system is booting.  Do not change this entry.
      ##
      127.0.0.1 localhost
      255.255.255.255 broadcasthost
      ::1 localhost

      # Local HTTP fixture targets.
      ${hostsToLines localHostAliases}
    '';
  };

  environment.etc."http-fixture/config.toml".source = httpFixtureConfigSource;

  environment.etc."caddy/http-fixture.caddyfile.template".text = ''
    {
    	admin off
    	auto_https off
    }

    ${lib.trim caddyPassThroughSnippets}

    ${lib.trim caddySites}
  '';

  system.activationScripts.extraActivation.text = lib.modules.mkAfter ''
    install -d -m 0755 -o root -g wheel ${httpFixtureStateDir}

    if [ ! -s ${httpFixtureCert} ] || [ ! -s ${httpFixtureKey} ] || [ "$(cat ${httpFixtureSanFile} 2>/dev/null || true)" != "${httpFixtureSanList}" ]; then
      rm -f ${httpFixtureCert} ${httpFixtureKey} ${httpFixtureSanFile}
      ${openssl} req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
        -subj "/CN=${builtins.head httpFixtureDomains}" \
        -addext "subjectAltName=${httpFixtureSanList}" \
        -keyout ${httpFixtureKey} \
        -out ${httpFixtureCert}
      printf '%s\n' "${httpFixtureSanList}" > ${httpFixtureSanFile}
      chmod 0600 ${httpFixtureKey}
      chmod 0644 ${httpFixtureCert}
      chmod 0644 ${httpFixtureSanFile}
    fi
    chmod 0755 ${httpFixtureStateDir}
    chmod 0600 ${httpFixtureKey}
    chmod 0644 ${httpFixtureCert}
    chmod 0644 ${httpFixtureSanFile}

    if ! security verify-cert -c ${httpFixtureCert} -p ssl -q >/dev/null 2>&1; then
      security add-trusted-cert -d -r trustRoot -p ssl -k /Library/Keychains/System.keychain ${httpFixtureCert}
    fi
  '';

  system.activationScripts.postActivation.text = lib.modules.mkAfter ''
    if [ -e /etc/static/hosts ] && { [ -L /etc/hosts ] || ! cmp -s /etc/static/hosts /etc/hosts; }; then
      hosts_tmp="$(mktemp)"
      cp /etc/static/hosts "$hosts_tmp"
      rm -f /etc/hosts
      cp "$hosts_tmp" /etc/hosts
      rm -f "$hosts_tmp"
      chown root:wheel /etc/hosts
      chmod 0644 /etc/hosts
      dscacheutil -flushcache || true
      killall -9 mDNSResponder || true
      killall -9 mDNSResponderHelper || true
    fi

    install -d -m 0755 -o root -g wheel /etc/caddy
    caddy_rendered="$(mktemp)"
    cp ${httpFixtureCaddyfileTemplate} "$caddy_rendered"
    ${caddyRenderPassThroughUpstreams}
    install -m 0644 -o root -g wheel "$caddy_rendered" ${httpFixtureCaddyfile}
    rm -f "$caddy_rendered"

    launchctl bootout system/org.nixos.http-fixture-lab 2>/dev/null || true
    launchctl bootout system/org.nixos.local-fixture-proxy 2>/dev/null || true
    launchctl kickstart -k system/org.nixos.http-fixture 2>/dev/null || true
    launchctl kickstart -k system/org.nixos.http-fixture-proxy 2>/dev/null || true
  '';

  launchd.daemons.http-fixture.serviceConfig = {
    Label = "org.nixos.http-fixture";
    ProgramArguments = [
      (lib.meta.getExe pkgs.http-fixture)
      "--config"
      httpFixtureConfigFile
    ];
    UserName = user;
    GroupName = "staff";
    RunAtLoad = true;
    KeepAlive = keepAliveUnlessStopped;
    ProcessType = "Background";
    StandardOutPath = httpFixtureLog;
    StandardErrorPath = httpFixtureLog;
  };

  launchd.daemons.http-fixture-proxy.serviceConfig = {
    Label = "org.nixos.http-fixture-proxy";
    ProgramArguments = [
      (lib.meta.getExe pkgs.caddy)
      "run"
      "--config"
      httpFixtureCaddyfile
      "--adapter"
      "caddyfile"
    ];
    UserName = "root";
    GroupName = "wheel";
    RunAtLoad = true;
    KeepAlive = keepAliveUnlessStopped;
    ProcessType = "Background";
    StandardOutPath = httpFixtureProxyLog;
    StandardErrorPath = httpFixtureProxyLog;
  };

  services.ghidra-mcp = {
    enable = true;
    httpHost = "127.0.0.1";
    httpPort = 8089;
    mcpHost = "127.0.0.1";
    mcpPort = 8090;
    allowScripts = true;
  };

  sops = {
    age.keyFile = "/Users/${config.system.primaryUser}/Library/Application Support/sops/age/keys.txt";
    defaultSopsFile = ../../secrets/secrets.yaml;
    validateSopsFiles = false;
    secrets = {
      github_ssh = {
        uid = 0;
        gid = 0;
        group = "wheel";
        owner = "root";
      };
      raycast-openrouter-api-key = {
        mode = "0644";
        group = "wheel";
        owner = "root";
        uid = 0;
        gid = 0;
      };
    };
  };

}
