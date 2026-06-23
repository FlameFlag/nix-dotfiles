#!/usr/bin/env bash
set -euo pipefail

cache_dir=${1:?cache dir required}
bin_dir=${2:?bin dir required}

case "$(uname -s):$(uname -m)" in
Linux:x86_64)
  os=linux
  arch=x86_64
  ;;
Linux:aarch64)
  os=linux
  arch=arm64
  ;;
Darwin:arm64)
  os=darwin
  arch=arm64
  ;;
Darwin:x86_64)
  os=darwin
  arch=x86_64
  ;;
*)
  printf '%s\n' "unsupported duf platform: $(uname -s):$(uname -m)" >&2
  exit 1
  ;;
esac

tag=$(
  curl -fsSL --retry 3 https://api.github.com/repos/muesli/duf/releases/latest \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1
)
test -n "$tag"
version=${tag#v}

if command -v duf >/dev/null 2>&1 && duf --version | grep -q "$version"; then
  printf 'unchanged %s\n' "$tag"
  exit 0
fi

asset="duf_${version}_${os}_${arch}.tar.gz"
install_dir="${cache_dir}/${tag}-${os}-${arch}"
archive="${cache_dir}/${asset}"

mkdir -p "$cache_dir" "$install_dir" "$bin_dir"
curl -fsSL --retry 3 -o "$archive" "https://github.com/muesli/duf/releases/download/${tag}/${asset}"
rm -rf "$install_dir"
mkdir -p "$install_dir"
tar -xzf "$archive" -C "$install_dir"
chmod 0755 "${install_dir}/duf"
ln -sfn "${install_dir}/duf" "${bin_dir}/duf"

printf 'installed %s\n' "$tag"
