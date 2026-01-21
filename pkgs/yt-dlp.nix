{
  lib,
  python3Packages,
  atomicparsley,
  deno,
  fetchFromGitHub,
  ffmpeg-headless,
  installShellFiles,
  pandoc,
  rtmpdump,
}:

python3Packages.buildPythonApplication {
  pname = "yt-dlp";
  version = "2025.12.08-unstable-2026-01-19";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "yt-dlp";
    repo = "yt-dlp";
    rev = "c8680b65f79cfeb23b342b70ffe1e233902f7933";
    hash = "sha256-lX+dlnLOo65NymtKi9gqX4xsxiH9fsiLafKcaU++tIo=";
  };

  doCheck = false;

  build-system = with python3Packages; [ hatchling ];

  nativeBuildInputs = [
    installShellFiles
    pandoc
  ];

  dependencies = builtins.attrValues {
    build-curl-cffi = python3Packages.curl-cffi;
    inherit (python3Packages)
      brotli
      certifi
      cffi
      curl-cffi
      mutagen
      pycryptodomex
      requests
      secretstorage
      urllib3
      websockets
      yt-dlp-ejs
      ;
  };

  pythonRelaxDeps = [ "websockets" ];

  preBuild = ''
    python devscripts/make_lazy_extractors.py
  '';

  postBuild = ''
    python devscripts/prepare_manpage.py yt-dlp.1.temp.md
    pandoc -s -f markdown-smart -t man yt-dlp.1.temp.md -o yt-dlp.1
    rm yt-dlp.1.temp.md

    mkdir -p completions/{bash,fish,zsh}
    python devscripts/bash-completion.py completions/bash/yt-dlp
    python devscripts/zsh-completion.py completions/zsh/_yt-dlp
    python devscripts/fish-completion.py completions/fish/yt-dlp.fish
  '';

  makeWrapperArgs = ''--prefix PATH : "${
    lib.makeBinPath [
      atomicparsley
      ffmpeg-headless
      deno
      rtmpdump
    ]
  }"'';

  checkPhase = ''
    output=$($out/bin/yt-dlp -v 2>&1 || true)
    if echo $output | grep -q "unsupported"; then
      echo "ERROR: Found \"unsupported\" string in yt-dlp -v output."
      exit 1
    fi
  '';

  postInstall = ''
    installManPage yt-dlp.1

    installShellCompletion \
      --bash completions/bash/yt-dlp \
      --fish completions/fish/yt-dlp.fish \
      --zsh completions/zsh/_yt-dlp

    install -Dm644 Changelog.md README.md -t "$out/share/doc/yt_dlp"
    ln -s "$out/bin/yt-dlp" "$out/bin/youtube-dl"
  '';
}
