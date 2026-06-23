#!/usr/bin/env bash
# shellcheck shell=bash
set -euo pipefail

case ${BASH_SOURCE[0]} in
*/*) script_dir=${BASH_SOURCE[0]%/*} ;;
*) script_dir=. ;;
esac
script_dir=$(cd -P -- "$script_dir" && pwd -P)

# shellcheck disable=SC1091
source -p "$script_dir/../lib" entrypoint.sh
source_host_lib fs
source_host_lib host

require_arg_count 0 0 "$@"
require_commands git mktemp python3

toshy_root=${XDG_STATE_HOME:-$HOME/.local/state}/nix-dotfiles/toshy
toshy_repo="$toshy_root/Toshy"
toshy_ref=${TOSHY_REF:-Toshy_v26.06.0}
toshy_automation="$script_dir/toshy-setup.py"
repo_dir=$NIX_DOTFILES_REPO_ROOT
toshy_slice_merger="$repo_dir/packages/toshy/merge-slices.py"
toshy_slice_dir="$repo_dir/packages/toshy/slices"
# shellcheck disable=SC2016
config_path=$(run_host_user_bash 'printf "%s\n" "${XDG_CONFIG_HOME:-$HOME/.config}/toshy/toshy_config.py"')

require_file "$toshy_automation"
require_file "$toshy_slice_merger"
require_file "$toshy_slice_dir/keymapper_api.py"
require_file "$toshy_slice_dir/barebones_user_cfg.py"

hide_toshy_gnome_surfaces() {
  # shellcheck disable=SC2016
  run_host_user_bash '
    set -euo pipefail

    set_no_display() {
      local desktop_file=${1:?desktop file is required}

      if [[ ! -f $desktop_file ]]; then
        return 0
      fi

      if grep -q "^[[:space:]]*NoDisplay=" "$desktop_file"; then
        sed -i "s/^[[:space:]]*NoDisplay=.*/NoDisplay=true/" "$desktop_file"
      else
        printf "\nNoDisplay=true\n" >>"$desktop_file"
      fi
    }

    data_home=${XDG_DATA_HOME:-$HOME/.local/share}
    config_home=${XDG_CONFIG_HOME:-$HOME/.config}
    for desktop_file in \
      "$data_home/applications/Toshy_Tray.desktop" \
      "$data_home/applications/app.toshy.preferences.desktop" \
      "$config_home/autostart/Toshy_Tray.desktop" \
      "$config_home/autostart/app.toshy.preferences.desktop"; do
      set_no_display "$desktop_file"
    done

    if command -v systemctl >/dev/null 2>&1; then
      systemctl --user disable --now toshy-tray.service >/dev/null 2>&1 || true
    fi
  '
}

ensure_dir "$toshy_root"
if [[ -d $toshy_repo/.git ]]; then
  git -C "$toshy_repo" fetch --depth 1 origin "$toshy_ref"
  git -C "$toshy_repo" checkout --force FETCH_HEAD
else
  remove_path "$toshy_repo"
  git clone --depth 1 --branch "$toshy_ref" https://github.com/RedBearAK/Toshy.git "$toshy_repo"
fi

# shellcheck disable=SC2016
if ! run_host_user_bash 'test -f "$1" && grep -q "SLICE_MARK_START: keymapper_api" "$1" && grep -q "SLICE_MARK_START: barebones_user_cfg" "$1"' "$config_path" \
  || [[ ${TOSHY_RUN_INSTALLER:-0} == 1 ]]; then
  printf '%s\n' 'toshy-kanata-chain: launching upstream Toshy barebones installer with nix-dotfiles automation.'
  automation_dir=$(mktemp -d)
  trap 'remove_path "$automation_dir"' EXIT

  install_args=(install --barebones-config)
  if [[ -n ${TOSHY_DISTRO_OVERRIDE:-} ]]; then
    install_args+=(--override-distro "$TOSHY_DISTRO_OVERRIDE")
  elif [[ -e /etc/NIXOS ]]; then
    install_args+=(--override-distro arch --skip-native)
  elif [[ -e /run/ostree-booted ]] || command -v rpm-ostree >/dev/null 2>&1; then
    install_args+=(--override-distro silverblue)
  fi
  if [[ ${TOSHY_SKIP_NATIVE:-0} == 1 && " ${install_args[*]} " != *" --skip-native "* ]]; then
    install_args+=(--skip-native)
  fi
  if [[ ${TOSHY_NO_DBUS_PYTHON:-0} == 1 ]]; then
    install_args+=(--no-dbus-python)
  fi

  install -m 0755 "$script_dir/sudo-shim.sh" "$automation_dir/sudo"
  host_sudo=$(run_host_user_bash 'command -v sudo || true')
  if [[ -z $host_sudo ]]; then
    die 'toshy-kanata-chain: sudo is not available on the host'
  fi

  python_bin=$(command -v python3)
  run_host_user env \
    PATH="$automation_dir:/run/wrappers/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/local/sbin:/usr/local/bin:$PATH" \
    TOSHY_SUDO="$host_sudo" \
    TOSHY_SUDO_SHIM_DIR="$automation_dir" \
    "$python_bin" "$toshy_automation" \
    "$toshy_repo/setup_toshy.py" "${install_args[@]}"
fi

run_host_user_bash_file \
  "$script_dir/toshy-merge.host.sh" \
  "$config_path" \
  "$toshy_slice_merger" \
  "$toshy_slice_dir" \
  "$script_dir/toshy-kanata.conf"

if run_host_user_bash 'command -v toshy-services-restart >/dev/null 2>&1'; then
  run_host_user toshy-services-restart || true
fi
hide_toshy_gnome_surfaces

printf '%s\n' 'toshy-kanata-chain: merged nix-dotfiles Toshy slices for Kanata virtual output'
