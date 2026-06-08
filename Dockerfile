# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=alpine:3.23
FROM ${BASE_IMAGE} AS dotfiles-test

ARG TEST_USER=dotfiles
ARG TEST_HOME=/home/dotfiles

RUN --mount=type=cache,target=/var/cache/apk \
    --mount=type=cache,target=/var/cache/dnf \
    <<EOF
set -eu

apk_packages="
  bash
  build-base
  ca-certificates
  cargo
  chezmoi
  curl
  curl-dev
  expat-dev
  file
  gcompat
  git
  libc6-compat
  libatomic
  libstdc++
  nushell
  openssl-dev
  starship
  tar
  unzip
  xz
  zlib-dev
  zellij
  zsh
"

dnf_packages="
  alsa-lib
  atk
  at-spi2-atk
  at-spi2-core
  bash
  ca-certificates
  cargo
  chezmoi
  cairo
  curl
  dbus-libs
  diffutils
  expat-devel
  libcurl-devel
  file
  findutils
  gcc
  git
  glibc
  gzip
  gtk3
  libX11
  libXcomposite
  libXdamage
  libXext
  libXfixes
  libXrandr
  libatomic
  libstdc++
  libxcb
  libxkbcommon
  make
  mesa-libgbm
  nspr
  nss
  nushell
  openssl-devel
  pango
  rust
  starship
  tar
  unzip
  xz
  zlib-devel
  zellij
  zsh
"

if command -v apk >/dev/null 2>&1; then
  apk add --update-cache ${apk_packages}
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y --setopt=install_weak_deps=False ${dnf_packages}
else
  printf 'unsupported package manager in base image\n' >&2
  exit 1
fi
EOF

RUN <<EOF
set -eu

if command -v apk >/dev/null 2>&1; then
  adduser -D -h "${TEST_HOME}" "${TEST_USER}"
elif command -v useradd >/dev/null 2>&1; then
  mkdir -p "$(dirname "${TEST_HOME}")"
  useradd --create-home --home-dir "${TEST_HOME}" "${TEST_USER}"
else
  printf 'missing user creation command\n' >&2
  exit 1
fi
EOF

USER ${TEST_USER}
ENV HOME=${TEST_HOME}
ENV CARGO_HOME=${TEST_HOME}/.cargo
ENV RUSTUP_HOME=${TEST_HOME}/.rustup
ENV CARGO_TARGET_DIR=/tmp/nix-dotfiles-target
ENV XDG_CACHE_HOME=${TEST_HOME}/.cache
ENV TMPDIR=${TEST_HOME}/.cache/tmp
ENV TMP=${TEST_HOME}/.cache/tmp
ENV TEMP=${TEST_HOME}/.cache/tmp
ENV PATH=${TEST_HOME}/.local/bin:${TEST_HOME}/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV CARGO_BUILD_JOBS=1
ENV DOTFILES_PROCESS_CAPTURE_TIMEOUT_SECS=180

RUN mkdir -p "${TMPDIR}"

WORKDIR /workspace/nix-dotfiles
COPY --chown=${TEST_USER}:${TEST_USER} . .

RUN --mount=type=cache,target=/tmp/nix-dotfiles-target,uid=1000,gid=1000 \
    cargo install --locked --path crates/chezmoi --root "${HOME}/.local"

RUN <<EOF
set -eu

chezmoi_targets="
  .zshrc
  .bashrc
  .gitconfig
  .gitignore_global
  .ssh/config
  .ssh/allowed_signers
  .codex
  .claude
  .cache/starship
  .cache/zellij
  .config
  .local/bin
  .local/share/applications
  .local/share/zellij
"

set --
for target in ${chezmoi_targets}; do
  set -- "$@" "${HOME}/${target}"
done

chezmoi \
  --source=/workspace/nix-dotfiles/dotfiles \
  --destination="${HOME}" \
  apply \
  --force \
  --no-tty \
  --parent-dirs \
  --exclude=scripts \
  "$@"
EOF

RUN scaffold --help >/dev/null
