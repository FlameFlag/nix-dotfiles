#!/usr/bin/env sh
# shellcheck shell=sh
set -eu

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
index_url=${ZIG_DOWNLOAD_INDEX_URL:-https://ziglang.org/download/index.json}
mirror_base=${ZIG_ARTIFACT_MIRROR_BASE:-https://zigmirror.com}
source_query=${ZIG_ARTIFACT_SOURCE_QUERY:-source=nix-dotfiles-bootstrap}
artifacts_file=${BOOTSTRAP_ZIG_ARTIFACTS:-"$script_dir/zig-artifacts.tsv"}

require_command() {
  if ! command -v "$1" > /dev/null 2>&1; then
    printf 'error: missing required command: %s\n' "$1" >&2
    exit 1
  fi
}

require_command curl
require_command jq
tmp_json=$(mktemp "${TMPDIR:-/tmp}/zig-index.XXXXXX")
tmp_tsv=$(mktemp "${TMPDIR:-/tmp}/zig-artifacts.XXXXXX")
cleanup() {
  rm -f "$tmp_json" "$tmp_tsv"
}
trap cleanup EXIT HUP INT TERM

curl -fsSL "$index_url" -o "$tmp_json"
version=$(jq -r '.master.version // empty' "$tmp_json")
if [ -z "$version" ]; then
  printf 'error: missing .master.version in %s\n' "$index_url" >&2
  exit 1
fi

jq -r --arg mirror_base "$mirror_base" --arg source_query "$source_query" '
  def pad($width):
    . + (" " * ($width - length));

  def artifact($target):
    .master[$target] as $artifact
    | if ($artifact == null) then
        error("missing .master." + $target)
      else
        [
          .master.version,
          $target,
          ($mirror_base + "/" + ($artifact.tarball | split("/") | last) + "?" + $source_query),
          $artifact.shasum
        ]
        | @tsv
      end;

  [
    ["#version", "target", "url", "sha256"],
    (artifact("aarch64-macos") | split("\t")),
    (artifact("x86_64-linux") | split("\t")),
    (artifact("aarch64-linux") | split("\t")),
    (artifact("x86_64-windows") | split("\t"))
  ] as $rows
  | [range(0; 3) as $i | ($rows | map(.[$i] | length) | max)] as $widths
  | ($rows[0][0] | pad($widths[0])) + "  "
    + ($rows[0][1] | pad($widths[1])) + "  "
    + ($rows[0][2] | pad($widths[2])) + "  "
    + $rows[0][3],
    ($rows[1:][] | (.[0] | pad($widths[0])) + "  "
      + (.[1] | pad($widths[1])) + "  "
      + (.[2] | pad($widths[2])) + "  "
      + .[3])
' "$tmp_json" > "$tmp_tsv"

mv "$tmp_tsv" "$artifacts_file"
tmp_tsv=

printf 'updated bootstrap Zig artifacts to %s\n' "$version"
