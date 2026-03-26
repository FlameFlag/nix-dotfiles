{ yt-dlp, fetchFromGitHub }:

yt-dlp.overridePythonAttrs (old: {
  version = "2026.03.17-unstable-2026-03-21";

  src = fetchFromGitHub {
    owner = "yt-dlp";
    repo = "yt-dlp";
    rev = "f01e1a1ced581c13f28c7da45eb6396cb9fff6e4";
    hash = "sha256-HEa+cZsOqVwgaaFtGqkLLA75wAm1mrHbPgo/SodpntA=";
  };
})
