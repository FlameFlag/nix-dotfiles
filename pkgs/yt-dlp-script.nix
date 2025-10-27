{
  writeShellApplication,
  cacert,
  uutils-findutils,
  ffmpeg-full,
  jq,
  gnused,
  yt-dlp,
}:

writeShellApplication {
  name = "yt-dlp-script";
  text = builtins.readFile ../scripts/yt-dlp-script.sh;
  runtimeInputs = [
    cacert
    uutils-findutils
    gnused
    ffmpeg-full
    jq
    yt-dlp
  ];
}
