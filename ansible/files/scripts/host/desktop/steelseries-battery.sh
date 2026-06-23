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
source_host_lib udev

require_arg_count 0 0 "$@"

rules_file=/etc/udev/rules.d/70-steelseries-arctis-battery.rules
rules=$(<"$script_dir/steelseries.rules")

install_host_udev_rules "$rules_file" "$rules"

printf '%s\n' 'steelseries-arctis-battery: installed udev rules'
