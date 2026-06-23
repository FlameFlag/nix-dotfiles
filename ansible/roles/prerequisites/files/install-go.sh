#!/usr/bin/env bash
set -euo pipefail

root=${1:?cache root is required}
bin_dir=${2:?bin dir is required}

case "$(uname -s):$(uname -m)" in
Darwin:arm64)
  goos=darwin
  goarch=arm64
  ;;
Darwin:x86_64)
  goos=darwin
  goarch=amd64
  ;;
Linux:aarch64)
  goos=linux
  goarch=arm64
  ;;
Linux:x86_64)
  goos=linux
  goarch=amd64
  ;;
*)
  printf '%s\n' "unsupported Go platform: $(uname -s):$(uname -m)" >&2
  exit 1
  ;;
esac

version=$(curl -fsSL --retry 3 'https://go.dev/dl/?mode=json' \
  | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  | head -n 1)
test -n "$version"

root_name="${version}.${goos}-${goarch}"
asset="${root_name}.tar.gz"
archive="${root}/${asset}"
extract_dir="${root}/extract"
install_dir="${root}/${root_name}"

mkdir -p "$root" "$bin_dir"
curl -fsSL --retry 3 -o "$archive" "https://go.dev/dl/${asset}"
rm -rf "$extract_dir" "$install_dir"
mkdir -p "$extract_dir"
tar -xzf "$archive" -C "$extract_dir"
mv "$extract_dir/go" "$install_dir"
ln -sfn "$install_dir/bin/go" "$bin_dir/go"
ln -sfn "$install_dir/bin/gofmt" "$bin_dir/gofmt"
