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
  ca-certificates
  curl
  file
  gcompat
  git
  libc6-compat
  libatomic
  libstdc++
  tar
  unzip
  xz
  zsh
"

dnf_packages="
  bash
  ca-certificates
  curl
  file
  findutils
  git
  glibc
  gzip
  libatomic
  libstdc++
  musl-libc
  tar
  unzip
  xz
  zsh
"

if command -v apk >/dev/null 2>&1; then
  apk add --update-cache ${apk_packages}
elif command -v dnf >/dev/null 2>&1; then
  dnf install -y --setopt=install_weak_deps=False ${dnf_packages}

  tmpdir="$(mktemp -d)"
  trap 'rm -rf "$tmpdir"' EXIT
  alpine_repo="https://dl-cdn.alpinelinux.org/alpine/v3.23/main/$(uname -m)"
  curl -fsSL "${alpine_repo}/APKINDEX.tar.gz" | tar -xzO APKINDEX > "$tmpdir/APKINDEX"
  for package in libgcc 'libstdc++'; do
    version="$(
      awk -v package="$package" '
        BEGIN { RS = ""; FS = "\n" }
        {
          name = ""
          version = ""
          for (i = 1; i <= NF; i++) {
            if ($i ~ /^P:/) name = substr($i, 3)
            if ($i ~ /^V:/) version = substr($i, 3)
          }
          if (name == package) {
            print version
            exit
          }
        }
      ' "$tmpdir/APKINDEX"
    )"
    archive="${package}-${version}.apk"
    curl -fsSL "${alpine_repo}/${archive}" -o "$tmpdir/$archive"
    tar --warning=no-unknown-keyword -xzf "$tmpdir/$archive" -C "$tmpdir"
  done
  musl_libdir="$(cat /etc/ld-musl-*.path)"
  cp -a "$tmpdir/usr/lib"/libgcc_s.so.1 "$tmpdir/usr/lib"/libstdc++.so.6* "$musl_libdir"
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

RUN ./bootstrap/bootstrap.sh

RUN <<EOF
set -eu

node_target="$(readlink "${HOME}/.local/bin/node")"
case "$node_target" in
  "${HOME}/.local/opt/node/"*/bin/node) ;;
  *) printf 'node is not bootstrap-managed: %s\n' "$node_target" >&2; exit 1 ;;
esac

node --version
npm --version
npx --version
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

doctor_output="$(./bootstrap/doctor.sh doctor)"
printf '%s\n' "$doctor_output"
case "$doctor_output" in
  *error:CommandFailed*) exit 1 ;;
esac
EOF
