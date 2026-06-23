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
source_host_lib cache
source_host_lib host

require_arg_count 0 0 "$@"
require_commands cargo git

staging=$(fresh_host_staging_dir kanata)
install_root=$staging/root
repo_dir=$NIX_DOTFILES_REPO_ROOT
kanata_config="$repo_dir/dotfiles/dot_config/kanata/kanata.kbd"

require_file "$kanata_config"

cargo install \
  --git https://github.com/jtroo/kanata \
  kanata \
  --features cmd \
  --root "$install_root" \
  --force \
  --locked

install_host_bin "$install_root/bin/kanata" kanata

host_user=$(run_host_user_bash 'id -un')
require_non_empty "$host_user" 'kanata: failed to detect host user'

run_host_bash_file \
  "$script_dir/kanata.host.sh" \
  "$host_user" \
  "$kanata_config" \
  "$script_dir/uinput.rules" \
  "$script_dir/kanata.service"

printf '%s\n' 'kanata: installed /etc/kanata/kanata.kbd and enabled kanata-main.service'
printf '%s\n' 'kanata: Toshy should target /run/kanata-main/main'
