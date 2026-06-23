#!/usr/bin/env bash
set -euo pipefail

runtime_dir="${XDG_CONFIG_HOME:-$HOME/.config}/toshy"
marker="$runtime_dir/.nix-dotfiles-toshy-version"

mkdir -p "$runtime_dir"

if [[ ! -f "$runtime_dir/toshy_config.py" ]] \
  || [[ ! -f "$marker" ]] \
  || [[ "$(cat "$marker" 2>/dev/null || true)" != "$TOSHY_SHARE" ]]; then
  tmp_dir="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/toshy-runtime.XXXXXX")"
  cleanup() {
    rm -rf "$tmp_dir"
  }
  trap cleanup EXIT

  cp -R "$TOSHY_SHARE/." "$tmp_dir/"
  chmod -R u+rwX "$tmp_dir"
  chmod -R u+rwX "$runtime_dir" 2>/dev/null || true
  rm -rf "$runtime_dir/assets" \
    "$runtime_dir/cosmic-dbus-service" \
    "$runtime_dir/default-toshy-config" \
    "$runtime_dir/kwin-dbus-service" \
    "$runtime_dir/scripts" \
    "$runtime_dir/systemd-user-service-units" \
    "$runtime_dir/toshy_common" \
    "$runtime_dir/toshy_gui" \
    "$runtime_dir/wlroots-dbus-service" \
    "$runtime_dir/wlroots-dev"
  cp -R "$tmp_dir/." "$runtime_dir/"
  printf '%s\n' "$TOSHY_SHARE" >"$marker"
fi

if [[ -z "${XDG_SESSION_TYPE:-}" ]]; then
  sleep 2
  echo "Toshy Config Service: XDG_SESSION_TYPE not set. Restarting service." >&2
  exit 1
fi

if [[ "${XDG_SESSION_TYPE:-}" == "x11" ]] && command -v xset >/dev/null 2>&1; then
  until xset -q >/dev/null 2>&1; do
    echo "Toshy Config Service: X server not ready?" >&2
    sleep 2
  done
fi

pkill -f "bin/xwaykeyz" || true
pkill -f "bin/keyszer" || true
pkill -f "bin/xkeysnail" || true

exec "$TOSHY_XWAYKEYZ" -w -c "$runtime_dir/toshy_config.py"
