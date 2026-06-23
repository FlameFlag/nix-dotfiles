#!/usr/bin/env bash
set -euo pipefail

cache_dir=${1:?cache dir required}
bin_dir=${2:?bin dir required}

case "$(uname -s):$(uname -m)" in
Linux:x86_64) triple=x86_64-unknown-linux-musl ;;
Linux:aarch64) triple=aarch64-unknown-linux-musl ;;
Darwin:arm64) triple=aarch64-apple-darwin ;;
Darwin:x86_64) triple=x86_64-apple-darwin ;;
*)
  printf '%s\n' "unsupported jj platform: $(uname -s):$(uname -m)" >&2
  exit 1
  ;;
esac

tag=$(
  curl -fsSL --retry 3 https://api.github.com/repos/jj-vcs/jj/releases/latest \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1
)
test -n "$tag"
version=${tag#v}

if command -v jj >/dev/null 2>&1 && jj --version | grep -q "jj ${version}"; then
  printf 'unchanged %s\n' "$tag"
  exit 0
fi

asset="jj-${tag}-${triple}.tar.gz"
install_dir="${cache_dir}/${tag}-${triple}"
archive="${cache_dir}/${asset}"

mkdir -p "$cache_dir" "$bin_dir" "$install_dir"
curl -fsSL --retry 3 -o "$archive" "https://github.com/jj-vcs/jj/releases/download/${tag}/${asset}"
tar -xzf "$archive" -C "$install_dir"
chmod 0755 "${install_dir}/jj"
ln -sfn "${install_dir}/jj" "${bin_dir}/jj"

printf 'installed %s\n' "$tag"
