#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC2016
set -euo pipefail

case ${BASH_SOURCE[0]} in
*/*) script_dir=${BASH_SOURCE[0]%/*} ;;
*) script_dir=. ;;
esac
script_dir=$(cd -P -- "$script_dir" && pwd -P)

# shellcheck disable=SC1091
source -p "$script_dir/../lib" entrypoint.sh
source_host_lib host

require_arg_count 0 0 "$@"

merge_rustdesk_options='
set -euo pipefail

merge_rustdesk_config() {
  local config_file=${1:?config file is required}
  local config_dir tmp_file

  config_dir=${config_file%/*}
  mkdir -p "$config_dir"
  touch "$config_file"
  tmp_file=$(mktemp)

  awk '"'"'
    BEGIN {
      in_options = 0
      seen_options = 0
      seen_direct_server = 0
      seen_direct_access_port = 0
    }

    function emit_missing_options() {
      if (!seen_direct_server) {
        print "direct-server = \"Y\""
      }
      if (!seen_direct_access_port) {
        print "direct-access-port = \"21118\""
      }
    }

    /^\[options\][[:space:]]*$/ {
      seen_options = 1
      in_options = 1
      print
      next
    }

    /^\[/ {
      if (in_options) {
        emit_missing_options()
      }
      in_options = 0
      print
      next
    }

    in_options && /^[[:space:]]*direct-server[[:space:]]*=/ {
      print "direct-server = \"Y\""
      seen_direct_server = 1
      next
    }

    in_options && /^[[:space:]]*direct-access-port[[:space:]]*=/ {
      print "direct-access-port = \"21118\""
      seen_direct_access_port = 1
      next
    }

    { print }

    END {
      if (!seen_options) {
        if (NR > 0) {
          print ""
        }
        print "[options]"
        print "direct-server = \"Y\""
        print "direct-access-port = \"21118\""
      } else if (in_options) {
        emit_missing_options()
      }
    }
  '"'"' "$config_file" >"$tmp_file"

  mv "$tmp_file" "$config_file"
}

merge_rustdesk_config "$HOME/.config/rustdesk/RustDesk2.toml"
'

remove_rustdesk_flatpak() {
  if ! host_has_command flatpak; then
    return 0
  fi

  run_host_user flatpak uninstall --user --noninteractive com.rustdesk.RustDesk >/dev/null 2>&1 || true
  run_host flatpak uninstall --system --noninteractive com.rustdesk.RustDesk >/dev/null 2>&1 || true
}

install_rustdesk_desktop_entry() {
  # shellcheck disable=SC2016
  run_host_user_bash '
    set -euo pipefail

    data_home=${XDG_DATA_HOME:-$HOME/.local/share}
    config_home=${XDG_CONFIG_HOME:-$HOME/.config}
    applications_dir="$data_home/applications"
    autostart_file="$config_home/autostart/rustdesk.desktop"
    desktop_file="$applications_dir/rustdesk.desktop"

    install -d -m 0755 "$applications_dir"
    cat >"$desktop_file" <<EOF
[Desktop Entry]
Type=Application
Version=1.5
Name=RustDesk
GenericName=Remote Desktop
Comment=Virtual and remote desktop access
Exec=rustdesk %u
Icon=rustdesk
Terminal=false
StartupNotify=true
StartupWMClass=rustdesk
Categories=Network;RemoteAccess;
MimeType=x-scheme-handler/rustdesk;
EOF
    chmod 0644 "$desktop_file"

    if [[ -f $autostart_file ]]; then
      install -d -m 0755 "${autostart_file%/*}"
      cp "$desktop_file" "$autostart_file"
      printf "%s\n" "X-GNOME-Autostart-enabled=true" >>"$autostart_file"
    fi

    if command -v update-desktop-database >/dev/null 2>&1; then
      update-desktop-database "$applications_dir" >/dev/null 2>&1 || true
    fi
  '
}

if ! host_has_command rustdesk; then
  printf '%s\n' 'rustdesk-tailscale: rustdesk is not installed; add it to the Spectrum image' >&2
  exit 0
fi

remove_rustdesk_flatpak
install_rustdesk_desktop_entry
run_host_user_bash "$merge_rustdesk_options"
if run_host bash -c 'rpm -q rustdesk >/dev/null 2>&1'; then
  run_host_bash "$merge_rustdesk_options"
  run_host systemctl restart rustdesk.service
fi

if host_has_command tailscale; then
  run_host systemctl enable --now tailscaled 2>/dev/null || true
  if ! run_host_user tailscale status >/dev/null 2>&1; then
    printf '%s\n' 'rustdesk-tailscale: tailscale is installed but not authenticated; run tailscale up on this host' >&2
  fi
else
  printf '%s\n' 'rustdesk-tailscale: tailscale is not installed; install the tailscale host tool before relying on direct IP access' >&2
fi
