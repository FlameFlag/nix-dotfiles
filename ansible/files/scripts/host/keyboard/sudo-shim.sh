#!/usr/bin/env bash
set -euo pipefail

if [[ ${1-} == "-k" ]]; then
  exit 0
fi
if [[ ${1-} == "-n" ]]; then
  shift
fi

runner=${TOSHY_SYSTEM_RUNNER:-$HOME/.local/bin/system-runner}
if [[ ! -x $runner ]]; then
  printf '%s\n' "toshy-kanata-chain: required system runner is not executable: $runner" >&2
  exit 127
fi

sudo_bin=${TOSHY_SUDO:-}
if [[ -z $sudo_bin ]]; then
  shim_path=$(readlink -f -- "$0")
  while IFS= read -r candidate; do
    if [[ $(readlink -f -- "$candidate") != "$shim_path" ]]; then
      sudo_bin=$candidate
      break
    fi
  done < <(type -P -a sudo || true)
fi
if [[ -z $sudo_bin ]]; then
  printf '%s\n' 'toshy-kanata-chain: sudo is not available on PATH' >&2
  exit 127
fi

exec "$sudo_bin" -n "$runner" -- "$@"
