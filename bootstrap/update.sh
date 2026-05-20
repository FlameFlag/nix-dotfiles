#!/usr/bin/env sh
# shellcheck shell=sh
set -eu

: "${HOME:?HOME must be set}"

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
local_bin="${HOME}/.local/bin"

zig_bootstrap_version() {
  artifacts_file=${BOOTSTRAP_ZIG_ARTIFACTS:-"$script_dir/zig-artifacts.tsv"}

  while read -r artifact_version _; do
    case "${artifact_version:-}" in
    '' | '#'*)
      continue
      ;;
    esac

    printf '%s\n' "$artifact_version"
    return 0
  done <"$artifacts_file"

  printf 'error: no Zig bootstrap artifacts found in %s\n' "$artifacts_file" >&2
  return 1
}

zig_min="${BOOTSTRAP_ZIG_VERSION:-$(zig_bootstrap_version)}"

require_bootstrap_ready() {
  if [ ! -x "$local_bin/zig" ]; then
    printf 'error: bootstrap has not installed %s yet; run bootstrap/bootstrap.sh first\n' "$local_bin/zig" >&2
    exit 1
  fi

  actual=$("$local_bin/zig" version 2>/dev/null) || {
    printf 'error: failed to run %s; run bootstrap/bootstrap.sh again\n' "$local_bin/zig" >&2
    exit 1
  }
  if [ "$actual" != "$zig_min" ]; then
    printf 'error: bootstrap Zig is %s, expected %s; run bootstrap/bootstrap.sh first\n' "$actual" "$zig_min" >&2
    exit 1
  fi
}

if [ "$#" -gt 0 ]; then
  if [ "$#" -ne 1 ] || [ "$1" != "update" ]; then
    printf 'usage: %s [update]\n' "$0" >&2
    exit 1
  fi
fi
mkdir -p "$local_bin"

# Put the managed bin directory first so helper commands resolve to the
# bootstrap-managed tools before external installs.
require_bootstrap_ready
export PATH="$local_bin:$PATH"
BOOTSTRAP_REPO_DIR="$repo_dir" exec "$local_bin/zig" run \
  --dep bootstrap --dep common -Mroot="$script_dir/dev_tools/main.zig" \
  --dep common -Mbootstrap="$repo_dir/lib/zig/bootstrap/root.zig" \
  -Mcommon="$repo_dir/lib/zig/common/root.zig" \
  -- update
