{
  lib,
  stdenv,
  makeWrapper,
  cacert,
  gh,
  zig,
}:

stdenv.mkDerivation {
  pname = "gh-hide-comment";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ../scripts/gh-hide-comment;
    fileset = ../scripts/gh-hide-comment;
  };

  nativeBuildInputs = [
    makeWrapper
    zig
  ];

  strictDeps = true;

  doCheck = true;

  postInstall = ''
    install -Dm755 "$out/bin/gh-hide-comment" "$out/libexec/gh-hide-comment/gh-hide-comment"
    rm "$out/bin/gh-hide-comment"
    makeWrapper "$out/libexec/gh-hide-comment/gh-hide-comment" "$out/bin/gh-hide-comment" \
      --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
      --prefix PATH : ${
        lib.makeBinPath [
          gh
        ]
      }
  '';

  meta = {
    description = "Hide GitHub comments via the GraphQL minimizeComment mutation";
    mainProgram = "gh-hide-comment";
  };
}
