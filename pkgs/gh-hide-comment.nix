{
  lib,
  runCommand,
  makeWrapper,
  nushell,
  cacert,
  gh,
}:

runCommand "gh-hide-comment"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta = {
      description = "Hide GitHub comments via the GraphQL minimizeComment mutation";
      mainProgram = "gh-hide-comment";
    };
  }
  ''
    mkdir -p "$out/libexec/gh-hide-comment" "$out/bin"
    install -m 0755 ${../scripts/gh-hide-comment.nu} "$out/libexec/gh-hide-comment/gh-hide-comment.nu"
    install -m 0644 ${../scripts/hide-comment.gql}   "$out/libexec/gh-hide-comment/hide-comment.gql"
    makeWrapper "$out/libexec/gh-hide-comment/gh-hide-comment.nu" "$out/bin/gh-hide-comment" \
      --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
      --prefix PATH : ${
        lib.makeBinPath [
          nushell
          gh
        ]
      }
  ''
