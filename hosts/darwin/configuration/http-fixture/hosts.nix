{ config, lib, ... }:
let
  settings = import ./settings.nix { inherit config lib; };
in
{
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
      ${settings.hostsToLines settings.hostAliases}
    '';
  };

  system.activationScripts.postActivation.text = lib.mkAfter ''
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
  '';
}
