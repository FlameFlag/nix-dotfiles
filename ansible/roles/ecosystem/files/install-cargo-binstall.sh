#!/usr/bin/env bash
set -euo pipefail

cache_dir=${1:?cache dir required}
bin_dir=${2:?bin dir required}

case "$(uname -s):$(uname -m)" in
Linux:x86_64)
  triple=x86_64-unknown-linux-gnu
  ext=tgz
  ;;
Linux:aarch64)
  triple=aarch64-unknown-linux-gnu
  ext=tgz
  ;;
Darwin:arm64)
  triple=aarch64-apple-darwin
  ext=zip
  ;;
Darwin:x86_64)
  triple=x86_64-apple-darwin
  ext=zip
  ;;
*)
  printf '%s\n' "unsupported cargo-binstall platform: $(uname -s):$(uname -m)" >&2
  exit 1
  ;;
esac

tag=$(
  curl -fsSL --retry 3 https://api.github.com/repos/cargo-bins/cargo-binstall/releases/latest \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1
)
test -n "$tag"

if [ -x "${bin_dir}/cargo-binstall" ] && "${bin_dir}/cargo-binstall" --version | grep -q "${tag#v}"; then
  printf 'unchanged %s\n' "$tag"
  exit 0
fi

asset="cargo-binstall-${triple}.${ext}"
install_dir="${cache_dir}/${tag}-${triple}"
archive="${cache_dir}/${asset}"

mkdir -p "$cache_dir" "$install_dir" "$bin_dir"
curl -fsSL --retry 3 -o "$archive" "https://github.com/cargo-bins/cargo-binstall/releases/download/${tag}/${asset}"
rm -rf "$install_dir"
mkdir -p "$install_dir"
case "$ext" in
tgz) tar -xzf "$archive" -C "$install_dir" ;;
zip) unzip -q "$archive" -d "$install_dir" ;;
esac
install -m 0755 "${install_dir}/cargo-binstall" "${bin_dir}/cargo-binstall"

printf 'installed %s\n' "$tag"
