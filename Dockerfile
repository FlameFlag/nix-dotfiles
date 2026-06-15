# syntax=docker/dockerfile:1.7

ARG BASE_IMAGE=alpine:3.23
FROM ${BASE_IMAGE} AS dotfiles-test

ARG TARGETARCH
ARG SCAFFOLD_VERSION=rolling
ARG STARSHIP_VERSION=v1.25.1
ARG TEST_USER=dotfiles
ARG TEST_UID=1000
ARG TEST_GID=${TEST_UID}
ARG TEST_HOME=/home/dotfiles
ARG ZELLIJ_VERSION=v0.44.3

RUN --mount=type=cache,target=/var/cache/apk \
    --mount=type=cache,target=/var/cache/dnf,sharing=locked \
    <<EOF
set -eu

apk_packages="
  bash
  build-base
  ca-certificates
  chezmoi
  curl
  curl-dev
  expat-dev
  file
  gcompat
  git
  go
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
  golang
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
  tar
  unzip
  xz
  zlib-devel
  zsh
"

if command -v apk >/dev/null 2>&1; then
  apk add --update-cache --no-progress ${apk_packages}
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y --setopt=install_weak_deps=False ${dnf_packages}
else
  printf 'unsupported package manager in base image\n' >&2
  exit 1
fi
EOF

RUN <<EOF
set -eu

case "${TARGETARCH}" in
  amd64)
    scaffold_package="scaffold-rolling-x86_64-unknown-linux-gnu"
    ;;
  *)
    printf 'unsupported Scaffold release architecture: %s\n' "${TARGETARCH}" >&2
    exit 1
    ;;
esac

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

curl \
  -fsSL \
  --retry 3 \
  -o "${tmp_dir}/scaffold.tar.gz" \
  "https://github.com/FlameFlag/scaffold/releases/download/${SCAFFOLD_VERSION}/${scaffold_package}.tar.gz"
tar -xzf "${tmp_dir}/scaffold.tar.gz" -C "${tmp_dir}"
install -m 0755 "${tmp_dir}/${scaffold_package}/scaffold" /usr/local/bin/scaffold
scaffold --help >/dev/null
EOF

RUN <<EOF
set -eu

case "${TARGETARCH}" in
  amd64)
    starship_package="starship-x86_64-unknown-linux-musl"
    zellij_package="zellij-x86_64-unknown-linux-musl"
    ;;
  *)
    printf 'unsupported release binary architecture: %s\n' "${TARGETARCH}" >&2
    exit 1
    ;;
esac

install_tar_binary() {
  binary="$1"
  url="$2"

  if command -v "${binary}" >/dev/null 2>&1; then
    return 0
  fi

  tmp_dir="$(mktemp -d)"
  curl -fsSL --retry 3 -o "${tmp_dir}/${binary}.tar.gz" "${url}"
  tar -xzf "${tmp_dir}/${binary}.tar.gz" -C "${tmp_dir}"
  install -m 0755 "${tmp_dir}/${binary}" "/usr/local/bin/${binary}"
  rm -rf "${tmp_dir}"
}

install_tar_binary \
  starship \
  "https://github.com/starship/starship/releases/download/${STARSHIP_VERSION}/${starship_package}.tar.gz"
install_tar_binary \
  zellij \
  "https://github.com/zellij-org/zellij/releases/download/${ZELLIJ_VERSION}/${zellij_package}.tar.gz"

starship --version >/dev/null
zellij --version >/dev/null
EOF

RUN <<EOF
set -eu

if command -v apk >/dev/null 2>&1; then
  addgroup -g "${TEST_GID}" "${TEST_USER}"
  adduser -D -G "${TEST_USER}" -h "${TEST_HOME}" -u "${TEST_UID}" "${TEST_USER}"
elif command -v useradd >/dev/null 2>&1; then
  mkdir -p "$(dirname "${TEST_HOME}")"
  groupadd --gid "${TEST_GID}" "${TEST_USER}"
  useradd --uid "${TEST_UID}" --gid "${TEST_GID}" --create-home --home-dir "${TEST_HOME}" "${TEST_USER}"
else
  printf 'missing user creation command\n' >&2
  exit 1
fi
EOF

USER ${TEST_USER}
ENV HOME=${TEST_HOME}
ENV XDG_CACHE_HOME=${TEST_HOME}/.cache
ENV TMPDIR=${TEST_HOME}/.cache/tmp
ENV TMP=${TEST_HOME}/.cache/tmp
ENV TEMP=${TEST_HOME}/.cache/tmp
ENV PATH=${TEST_HOME}/.local/bin:${TEST_HOME}/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ENV DOTFILES_PROCESS_CAPTURE_TIMEOUT_SECS=180
ENV GOTOOLCHAIN=auto
ENV GOCACHE=${TEST_HOME}/.cache/go-build
ENV GOMODCACHE=${TEST_HOME}/go/pkg/mod

RUN mkdir -p "${TMPDIR}" "${GOCACHE}" "${GOMODCACHE}" "${HOME}/.local/bin"

WORKDIR /workspace/nix-dotfiles

COPY --chown=${TEST_USER}:${TEST_USER} go.mod go.sum ./
RUN --mount=type=cache,target=/home/dotfiles/go/pkg/mod,uid=${TEST_UID},gid=${TEST_GID} \
    go mod download

COPY --chown=${TEST_USER}:${TEST_USER} cmd/ ./cmd/
COPY --chown=${TEST_USER}:${TEST_USER} internal/ ./internal/

RUN --mount=type=cache,target=/home/dotfiles/go/pkg/mod,uid=${TEST_UID},gid=${TEST_GID} \
    --mount=type=cache,target=/home/dotfiles/.cache/go-build,uid=${TEST_UID},gid=${TEST_GID} \
    GOBIN="${HOME}/.local/bin" go install ./cmd/chezmoi-support

COPY --chown=${TEST_USER}:${TEST_USER} . .

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
