#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)

uv_bin=${UV_BIN:-}
if [ -z "$uv_bin" ]; then
  if command -v uv >/dev/null 2>&1; then
    uv_bin=$(command -v uv)
  elif [ -x "$HOME/.local/bin/uv" ]; then
    uv_bin=$HOME/.local/bin/uv
  fi
fi

if [ -z "$uv_bin" ]; then
  if command -v curl >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- https://astral.sh/uv/install.sh | sh
  else
    printf '%s\n' "uv is missing and neither curl nor wget is available to install it" >&2
    exit 1
  fi
  uv_bin=$HOME/.local/bin/uv
fi

ansible_core_spec=${ANSIBLE_CORE_SPEC:-ansible-core}
ansible_package_spec=${ANSIBLE_PACKAGE_SPEC:-ansible}
ansible_uv_refresh=${ANSIBLE_UV_REFRESH:-true}

uv_tool_args=(tool run)
if [ "$ansible_uv_refresh" != "false" ] && [ "$ansible_uv_refresh" != "0" ]; then
  uv_tool_args+=(--refresh)
fi

cd "$repo_dir"
exec "$uv_bin" "${uv_tool_args[@]}" --from "$ansible_core_spec" --with "$ansible_package_spec" ansible-playbook ansible/playbooks/bootstrap.yml "$@"
