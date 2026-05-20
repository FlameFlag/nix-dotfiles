{
  pkgs,
  lib,
  ...
}:
let
  kanataPackage = pkgs.kanata-with-cmd;
  karabinerDriver = kanataPackage.passthru.darwinDriver;
  plist = pkgs.formats.plist { };

  kanataLabel = "org.nixos.kanata";
  kanataApp = "/Applications/Kanata.app";
  kanataStableBinary = "${kanataApp}/Contents/MacOS/kanata";
  kanataConfig = ../../dotfiles/dot_config/kanata/kanata-macos.kbd;
  kanataLaunchdPlist = "/Library/LaunchDaemons/${kanataLabel}.plist";
  kanataLog = "/var/log/kanata.log";

  karabinerVirtualHidLabel = "org.pqrs.service.daemon.Karabiner-VirtualHIDDevice-Daemon";
  karabinerDriverSupportStore = "${karabinerDriver}/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice";
  karabinerDriverSupport = "/Library/Application Support/org.pqrs/Karabiner-DriverKit-VirtualHIDDevice";
  karabinerVirtualHidDaemon = "${karabinerDriverSupport}/Applications/Karabiner-VirtualHIDDevice-Daemon.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Daemon";
  karabinerVirtualHidLogDir = "/var/log/karabiner";
  karabinerVirtualHidLog = "${karabinerVirtualHidLogDir}/virtual_hid_device_service.log";

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
  kanataInfoPlist = plist.generate "Kanata-Info.plist" {
    CFBundleDisplayName = "Kanata";
    CFBundleExecutable = "kanata";
    CFBundleIdentifier = kanataLabel;
    CFBundleName = "Kanata";
    CFBundlePackageType = "APPL";
    CFBundleShortVersionString = "1.0";
    CFBundleVersion = "1";
    LSUIElement = true;
  };
  keepAliveUnlessStopped = {
    Crashed = true;
    SuccessfulExit = false;
  };
in
{
  environment.systemPackages = [
    kanataPackage
    karabinerDriver
  ];

  system.activationScripts.extraActivation.text = lib.modules.mkAfter ''
    install -d -m 0755 -o root -g wheel ${kanataApp}/Contents/MacOS
    install -d -m 0755 -o root -g wheel ${karabinerVirtualHidLogDir}
    install -d -m 0755 -o root -g admin "/Library/Application Support/org.pqrs"
    rm -rf ${lib.escapeShellArg karabinerDriverSupport}
    /usr/bin/ditto ${lib.escapeShellArg karabinerDriverSupportStore} ${lib.escapeShellArg karabinerDriverSupport}
    chown -R root:wheel ${lib.escapeShellArg karabinerDriverSupport}
    chmod -R a+rX ${lib.escapeShellArg karabinerDriverSupport}
    install -m 0755 -o root -g wheel ${lib.meta.getExe kanataPackage} ${kanataStableBinary}
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

  system.activationScripts.postActivation.text = lib.modules.mkAfter ''
    if [ -f /Library/LaunchDaemons/${karabinerVirtualHidLabel}.plist ]; then
      launchctl bootstrap system /Library/LaunchDaemons/${karabinerVirtualHidLabel}.plist 2>/dev/null || true
      launchctl enable system/${karabinerVirtualHidLabel} 2>/dev/null || true
      launchctl kickstart -k system/${karabinerVirtualHidLabel} 2>/dev/null || true
    fi

    if [ -f ${kanataLaunchdPlist} ]; then
      launchctl bootstrap system ${kanataLaunchdPlist} 2>/dev/null || true
      launchctl enable system/${kanataLabel} 2>/dev/null || true
      launchctl kickstart -k system/${kanataLabel} 2>/dev/null || true
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
    StandardOutPath = kanataLog;
    StandardErrorPath = kanataLog;
  };

  launchd.daemons.karabiner-virtualhiddevice-daemon.serviceConfig = {
    Label = karabinerVirtualHidLabel;
    ProgramArguments = [
      karabinerVirtualHidDaemon
    ];
    KeepAlive = true;
    ProcessType = "Interactive";
    StandardOutPath = karabinerVirtualHidLog;
    StandardErrorPath = karabinerVirtualHidLog;
  };
}
