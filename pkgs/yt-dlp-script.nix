{
  lib,
  writeTextFile,
  nushell,
  makeWrapper,
  symlinkJoin,
  cacert,
  ffmpeg-full,
  yt-dlp,
}:

let
  script = writeTextFile {
    name = "yt-dlp-script";
    text = builtins.readFile ../scripts/yt-dlp-script.nu;
    executable = true;
    destination = "/bin/yt-dlp-script";
  };
in
symlinkJoin {
  name = "yt-dlp-script";
  paths = [ script ];
  nativeBuildInputs = [ makeWrapper ];
  postBuild = ''
    wrapProgram $out/bin/yt-dlp-script \
      --set SSL_CERT_FILE "${cacert}/etc/ssl/certs/ca-bundle.crt" \
      --prefix PATH : ${lib.makeBinPath [ nushell ffmpeg-full yt-dlp ]}
  '';
}
