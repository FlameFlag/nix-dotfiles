{
  pkgs,
  lib,
  config,
  ...
}:
let
  user = config.system.primaryUser;
  kanataApp = "/Applications/Kanata.app";
  kanataStableBinary = "${kanataApp}/Contents/MacOS/kanata";
  kanataConfig = ../../dotfiles/dot_config/kanata/kanata-macos.kbd;
  kanataSigningIdentity = "Kanata Local Code Signing";
  kanataSigningKeychain = "/Library/Keychains/System.keychain";
  kanataSigningOpenSslConfig = pkgs.writeText "kanata-codesign-openssl.cnf" ''
    [ req ]
    distinguished_name = dn
    x509_extensions = v3_req
    prompt = no
    [ dn ]
    CN = ${kanataSigningIdentity}
    [ v3_req ]
    keyUsage = critical, digitalSignature
    extendedKeyUsage = codeSigning
    basicConstraints = critical, CA:false
  '';
  kanataInfoPlist = pkgs.writeText "Kanata-Info.plist" (
    lib.generators.toPlist { escape = true; } {
      CFBundleDisplayName = "Kanata";
      CFBundleExecutable = "kanata";
      CFBundleIdentifier = "org.nixos.kanata";
      CFBundleName = "Kanata";
      CFBundlePackageType = "APPL";
      CFBundleShortVersionString = "1.0";
      CFBundleVersion = "1";
      LSUIElement = true;
    }
  );
  keepAliveUnlessStopped = {
    Crashed = true;
    SuccessfulExit = false;
  };
in
{
  environment.systemPackages = [
    pkgs.kanata-with-cmd
    pkgs.kanata-with-cmd.passthru.darwinDriver
  ];

  system.activationScripts.extraActivation.text = lib.mkAfter ''
    install -d -m 0755 -o root -g wheel ${kanataApp}/Contents/MacOS
    install -m 0755 -o root -g wheel ${lib.getExe pkgs.kanata-with-cmd} ${kanataStableBinary}
    install -m 0644 -o root -g wheel ${kanataInfoPlist} ${kanataApp}/Contents/Info.plist
    chmod 0644 ${kanataApp}/Contents/Info.plist
    chown -R root:wheel ${kanataApp}

    if ! security find-identity -v -p codesigning ${kanataSigningKeychain} | grep -Fq "${kanataSigningIdentity}"; then
      tmpdir="$(mktemp -d /tmp/kanata-codesign.XXXXXX)"
      trap 'rm -rf "$tmpdir"' EXIT
      openssl req -newkey rsa:2048 -nodes -keyout "$tmpdir/kanata.key" -x509 -days 3650 -out "$tmpdir/kanata.crt" -config ${kanataSigningOpenSslConfig}
      openssl pkcs12 -export -inkey "$tmpdir/kanata.key" -in "$tmpdir/kanata.crt" -out "$tmpdir/kanata.p12" -passout pass:kanata-local
      security import "$tmpdir/kanata.p12" -k ${kanataSigningKeychain} -P kanata-local -T /usr/bin/codesign
      security add-trusted-cert -d -r trustRoot -p codeSign -k ${kanataSigningKeychain} "$tmpdir/kanata.crt"
      rm -rf "$tmpdir"
      trap - EXIT
    fi

    if security find-identity -v -p codesigning ${kanataSigningKeychain} | grep -Fq "${kanataSigningIdentity}"; then
      codesign --force --keychain ${kanataSigningKeychain} --sign "${kanataSigningIdentity}" ${kanataApp}
    else
      codesign --force --sign - ${kanataApp}
    fi
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f ${kanataApp}
  '';

  system.activationScripts.postActivation.text = lib.mkAfter ''
    if [ -f /Library/LaunchDaemons/org.nixos.kanata.plist ]; then
      launchctl bootstrap system /Library/LaunchDaemons/org.nixos.kanata.plist 2>/dev/null || true
      launchctl enable system/org.nixos.kanata 2>/dev/null || true
      launchctl kickstart -k system/org.nixos.kanata 2>/dev/null || true
    fi
  '';

  launchd.daemons.kanata.serviceConfig = {
    ProgramArguments = [
      kanataStableBinary
      "--cfg"
      (toString kanataConfig)
    ];
    RunAtLoad = true;
    KeepAlive = keepAliveUnlessStopped;
    ProcessType = "Interactive";
    StandardOutPath = "/var/log/kanata.log";
    StandardErrorPath = "/var/log/kanata.log";
  };

  launchd.user.agents = {
    symlink-zsh-config = {
      script = ''
        for file in zprofile zshenv; do
          ln -sfn "/etc/''${file}" "/Users/${user}/.''${file}"
        done
      '';
      serviceConfig.RunAtLoad = true;
      serviceConfig.StartInterval = 0;
    };

    atuin-daemon.serviceConfig = {
      ProgramArguments = [
        (lib.getExe' pkgs.unstable.atuin "atuin")
        "daemon"
        "start"
      ];
      RunAtLoad = true;
      KeepAlive = keepAliveUnlessStopped;
      ProcessType = "Background";
      StandardOutPath = "/Users/${user}/Library/Logs/atuin-daemon.log";
      StandardErrorPath = "/Users/${user}/Library/Logs/atuin-daemon.log";
    };
  };
}
