# shellcheck shell=bash

config_path=${1:?Toshy config path is required}
slice_merger=${2:?Toshy slice merger is required}
slice_dir=${3:?Toshy slice directory is required}
dropin_source=${4:?systemd drop-in source is required}

if [[ ! -f $config_path ]]; then
  printf "%s\n" "toshy-kanata-chain: Toshy config was not found at $config_path" >&2
  exit 1
fi
if [[ ! -f $slice_merger ]]; then
  printf "%s\n" "toshy-kanata-chain: Toshy slice merger was not found at $slice_merger" >&2
  exit 1
fi
if [[ ! -d $slice_dir ]]; then
  printf "%s\n" "toshy-kanata-chain: Toshy slice directory was not found at $slice_dir" >&2
  exit 1
fi

config_dir=${config_path%/*}
service_dropin_dir="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/toshy-config.service.d"

install -d -m 0755 "$config_dir" "$service_dropin_dir"
python3 "$slice_merger" "$config_path" "$slice_dir"
install -m 0644 "$dropin_source" "$service_dropin_dir/10-nix-dotfiles.conf"
systemctl --user daemon-reload || true
