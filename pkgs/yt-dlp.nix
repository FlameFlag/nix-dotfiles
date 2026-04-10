{ yt-dlp, fetchFromGitHub }:

yt-dlp.overridePythonAttrs (old: {
  version = "2026.03.17-unstable-2026-04-07";

  src = fetchFromGitHub {
    owner = "yt-dlp";
    repo = "yt-dlp";
    rev = "a4acc4223289eeb4d32af7b798bfe6e9c38f4b8d";
    hash = "sha256-rmMiMZV7T51PVp/OXeh6J9KAqeM/NkoRhh9GWLpbQTM=";
  };
})
