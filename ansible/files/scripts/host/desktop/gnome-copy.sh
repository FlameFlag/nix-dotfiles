#!/usr/bin/env bash
set -euo pipefail

out_link=${1:?out link is required}
uuid=${2:?extension UUID is required}
destination=${3:?destination is required}
host_bin_dir=${4:?host bin dir is required}

if ! package_path=$(readlink -f "$out_link" 2>/dev/null); then
  package_path=$(readlink "$out_link")
fi
source_dir="$package_path/share/gnome-shell/extensions/$uuid"
if [[ ! -f "$source_dir/metadata.json" ]]; then
  printf "%s\n" "required file does not exist: $source_dir/metadata.json" >&2
  exit 1
fi

mkdir -p -- "${destination%/*}"
if [[ -e $destination ]]; then
  chmod -R u+rwX "$destination"
fi
rm -rf -- "$destination"
mkdir -p -- "$destination"
cp -R -- "$source_dir/." "$destination/"
if [[ -d $package_path/bin ]]; then
  mkdir -p -- "$host_bin_dir"
  while IFS= read -r -d "" source_path; do
    target_path="$host_bin_dir/${source_path##*/}"
    if [[ -e $target_path ]]; then
      chmod -R u+rwX "$target_path"
      rm -rf -- "$target_path"
    fi
  done < <(find "$package_path/bin" -mindepth 1 -maxdepth 1 -print0)
  cp -R -- "$package_path/bin/." "$host_bin_dir/"
fi
