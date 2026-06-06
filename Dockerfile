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
  tar
  unzip
  xz
  zlib-dev
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
  tar
  unzip
  xz
  zlib-devel
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
  useradd --create-home --home-dir "${TEST_HOME}" "${TEST_USER}"
else
  printf 'missing user creation command\n' >&2
  exit 1
fi
EOF

USER ${TEST_USER}
ENV HOME=${TEST_HOME}
ENV PATH=${TEST_HOME}/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

WORKDIR /workspace/nix-dotfiles
COPY --chown=${TEST_USER}:${TEST_USER} . .

RUN cargo run --locked --bin bootstrap -- bootstrap

RUN <<EOF
set -eu

if ldd --version 2>&1 | grep -qi musl; then
  if command -v node >/dev/null 2>&1; then
    printf 'node should be unsupported on musl Linux, but found: %s\n' "$(command -v node)" >&2
    exit 1
  fi
else
  node_target="$(readlink "${HOME}/.local/bin/node")"
  case "$node_target" in
    "${HOME}/.local/opt/node/"*/bin/node) ;;
    *) printf 'node is not bootstrap-managed: %s\n' "$node_target" >&2; exit 1 ;;
  esac
  case "$node_target" in
    *musl*) printf 'node still points at a musl build: %s\n' "$node_target" >&2; exit 1 ;;
  esac

  node --version
  npm --version
  npx --version
fi
EOF

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
  .config
  .local/bin
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
  --exclude=externals,scripts \
  "$@"
EOF

RUN <<EOF
set -eu

doctor_output="$(BOOTSTRAP_REPO_DIR=/workspace/nix-dotfiles bootstrap doctor)"
printf '%s\n' "$doctor_output"
case "$doctor_output" in
  *error:CommandFailed*) exit 1 ;;
esac
EOF
