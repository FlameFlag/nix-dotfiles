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
  version = "2025.11.12-unstable-2025-12-04";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "yt-dlp";
    repo = "yt-dlp";
    rev = "7ec6b9bc40ee8a21b11cce83a09a07a37014062e";
    hash = "sha256-Em8FLcCizSfvucg+KPuJyhFZ5MJ8STTjSpqaTD5xeKI=";
  };

  doCheck = false;

  postPatch = ''
    substituteInPlace yt_dlp/version.py \
      --replace-fail "UPDATE_HINT = None" 'UPDATE_HINT = "Nixpkgs/NixOS likely already contain an updated version.\n       To get it run nix-channel --update or nix flake update in your config directory."'
    substituteInPlace yt_dlp/networking/_curlcffi.py \
      --replace-fail "if curl_cffi_version != (0, 5, 10) and not (0, 10) <= curl_cffi_version < (0, 14)" \
      "if curl_cffi_version != (0, 5, 10) and not (0, 10) <= curl_cffi_version"
  '';

  build-system = with python3Packages; [ hatchling ];

  nativeBuildInputs = [
    installShellFiles
    pandoc
  ];

  dependencies = builtins.attrValues {
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
