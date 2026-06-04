{
  config,
  lib,
  pkgs,
  ...
}:
let
  settings = import ./settings.nix { inherit config lib; };
  openssl = lib.meta.getExe pkgs.openssl;
in
{
  system.activationScripts.extraActivation.text = lib.mkAfter ''
    install -d -m 0755 -o root -g wheel ${settings.stateDir}

    if [ ! -s ${settings.cert} ] || [ ! -s ${settings.key} ] || [ "$(cat ${settings.sanFile} 2>/dev/null || true)" != "${settings.sanList}" ]; then
      rm -f ${settings.cert} ${settings.key} ${settings.sanFile}
      ${openssl} req -x509 -newkey rsa:2048 -sha256 -nodes -days 3650 \
        -subj "/CN=${builtins.head settings.domains}" \
        -addext "subjectAltName=${settings.sanList}" \
        -keyout ${settings.key} \
        -out ${settings.cert}
      printf '%s\n' "${settings.sanList}" > ${settings.sanFile}
      chmod 0600 ${settings.key}
      chmod 0644 ${settings.cert}
      chmod 0644 ${settings.sanFile}
    fi
    chmod 0755 ${settings.stateDir}
    chmod 0600 ${settings.key}
    chmod 0644 ${settings.cert}
    chmod 0644 ${settings.sanFile}

    if ! security verify-cert -c ${settings.cert} -p ssl -q >/dev/null 2>&1; then
      security add-trusted-cert -d -r trustRoot -p ssl -k /Library/Keychains/System.keychain ${settings.cert}
    fi
  '';
}
