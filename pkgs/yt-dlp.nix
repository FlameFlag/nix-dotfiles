{ yt-dlp, fetchFromGitHub }:

yt-dlp.overridePythonAttrs (old: {
  version = "2026.03.17-unstable-2026-03-17";

  src = fetchFromGitHub {
    owner = "yt-dlp";
    repo = "yt-dlp";
    rev = "7fd74d10097833ebce0cb162e0ccf7825de9b768";
    hash = "sha256-A4LUCuKCjpVAOJ8jNoYaC3mRCiKH0/wtcsle0YfZyTA=";
  };
})
