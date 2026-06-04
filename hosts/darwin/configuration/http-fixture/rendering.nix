{ lib, settings }:
rec {
  snippetName =
    domain: "http_fixture_${lib.replaceStrings [ "." "-" ] [ "_" "_" ] domain}_pass_through";

  upstreamsPlaceholder =
    domain: "__HTTP_FIXTURE_UPSTREAMS_${lib.replaceStrings [ "." "-" ] [ "_" "_" ] domain}__";

  passThroughSnippet =
    domain:
    let
      route = settings.routes.${domain};
      passThrough = route.passThrough;
      realHost = passThrough.host or domain;
      scheme = passThrough.scheme or "https";
      upstreams =
        if (passThrough.upstreams or [ ]) != [ ] then
          passThrough.upstreams
        else if passThrough ? upstream then
          [ passThrough.upstream ]
        else
          [ ];
      upstreamText =
        if upstreams != [ ] then lib.concatStringsSep " " upstreams else upstreamsPlaceholder domain;
      tlsConfig = lib.optionalString (scheme == "https") ''
        			tls
        			tls_server_name ${realHost}
      '';
    in
    lib.optionalString (passThrough != null) ''
      (${snippetName domain}) {
      	reverse_proxy ${upstreamText} {
      		header_up Host ${realHost}
      		transport http {
      ${tlsConfig}
      		}
      	}
      }
    '';

  passThroughHandles =
    domain:
    let
      route = settings.routes.${domain};
      passThrough = route.passThrough;
      name = snippetName domain;
      exactPaths = passThrough.paths or [ ];
      pathPrefixes = passThrough.path_prefixes or [ ];
      websitePrefix = passThrough.website_prefix or null;
      exactPathHandles = lib.concatMapStringsSep "\n" (path: ''
        	handle ${path} {
        		import ${name}
        	}
      '') exactPaths;
      pathPrefixHandles = lib.concatMapStringsSep "\n" (pathPrefix: ''
        	handle ${pathPrefix}* {
        		import ${name}
        	}
      '') pathPrefixes;
      websiteHandles = lib.optionalString (websitePrefix != null) ''
        	handle ${websitePrefix} {
        		redir * ${websitePrefix}/ 308
        	}

        	handle_path ${websitePrefix}/* {
        		import ${name}
        	}
      '';
    in
    lib.optionalString (passThrough != null) ''
      ${lib.trim exactPathHandles}

      ${lib.trim pathPrefixHandles}

      ${lib.trim websiteHandles}
    '';

  siteBlock =
    domain:
    let
      route = settings.routes.${domain};
      names = [ domain ] ++ (route.aliases or [ ]);
    in
    ''
      https://${lib.concatStringsSep ", https://" names} {
      	bind 127.0.0.1 ::1
      	tls ${settings.cert} ${settings.key}

      	route {
      ${passThroughHandles domain}

      		handle {
      			reverse_proxy ${route.upstream}
      		}
      	}
      }
    '';

  passThroughSnippets = lib.concatMapStringsSep "\n" passThroughSnippet (
    lib.attrNames settings.routes
  );

  sites = lib.concatMapStringsSep "\n" siteBlock (lib.attrNames settings.routes);

  renderPassThroughUpstreams = lib.concatMapStringsSep "\n" (
    domain:
    let
      route = settings.routes.${domain};
      passThrough = route.passThrough;
      realHost = passThrough.host or domain;
      scheme = passThrough.scheme or "https";
      resolvers = passThrough.resolvers or [ ];
      placeholder = upstreamsPlaceholder domain;
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
  ) (lib.attrNames settings.routes);
}
