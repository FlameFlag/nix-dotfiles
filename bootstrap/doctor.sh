#!/usr/bin/env sh
# shellcheck shell=sh
set -eu

: "${HOME:?HOME must be set}"

script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH='' cd -- "$script_dir/.." && pwd)
local_bin="${HOME}/.local/bin"
cargo_home="${CARGO_HOME:-"$HOME/.cargo"}"
cargo_bin="$cargo_home/bin"
tools_json="$script_dir/dev_tools/tools/tools.json"
zig_min="${BOOTSTRAP_ZIG_VERSION:-0.17.0-dev.304+9787df942}"

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

  if [ ! -f "$tools_json" ]; then
    printf 'error: missing tools manifest: %s\n' "$tools_json" >&2
    exit 1
  fi
}

if [ "$#" -gt 0 ]; then
  if [ "$#" -ne 1 ] || [ "$1" != "doctor" ]; then
    printf 'usage: %s [doctor]\n' "$0" >&2
    exit 1
  fi
fi
# Doctor is intentionally read-only. It still needs the managed bin directories
# on PATH so it can explain whether each visible tool came from bootstrap or
# from an external install.
require_bootstrap_ready
export PATH="$local_bin:$cargo_bin:$PATH"
BOOTSTRAP_REPO_DIR="$repo_dir" BOOTSTRAP_TOOLS_JSON="$tools_json" exec "$local_bin/zig" run \
  --dep bootstrap --dep common -Mroot="$script_dir/dev_tools/main.zig" \
  --dep common -Mbootstrap="$repo_dir/lib/zig/bootstrap/root.zig" \
  -Mcommon="$repo_dir/lib/zig/common/root.zig" \
  -- doctor
