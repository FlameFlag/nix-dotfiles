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

policy_dir="$script_dir/tailscale-selinux"

install_or_enable_tailscale='
set -euo pipefail

if ! command -v tailscale >/dev/null 2>&1 || ! command -v tailscaled >/dev/null 2>&1; then
  printf "%s\n" "tailscale-bluefin: Tailscale is not installed; add it to the Spectrum image and switch to the rebuilt image" >&2
  exit 0
fi

if command -v tailscaled >/dev/null 2>&1; then
  systemctl enable tailscaled
  systemctl start tailscaled || true
fi
'

run_host_bash "$install_or_enable_tailscale"

install_tailscale_selinux_policy='
set -euo pipefail

policy_dir=${1:?policy directory is required}
policy_makefile=/usr/share/selinux/devel/Makefile

if ! command -v getenforce >/dev/null 2>&1 || [[ $(getenforce 2>/dev/null || true) == Disabled ]]; then
  exit 0
fi

if [[ ! -f $policy_makefile ]]; then
  printf "%s\n" "tailscale-bluefin: selinux-policy-devel is not installed; add it to the Spectrum image to build the tailscaled SELinux policy" >&2
  exit 0
fi

for file in tailscaled.te tailscaled.fc tailscaled.if; do
  if [[ ! -f $policy_dir/$file ]]; then
    die "tailscale-bluefin: missing SELinux policy source: $policy_dir/$file"
  fi
done

require_commands awk checkmodule grep install make pgrep ps semodule semodule_package sha256sum restorecon systemctl

policy_hash=$(
  cd "$policy_dir"
  sha256sum tailscaled.te tailscaled.fc tailscaled.if | sha256sum | awk "{print \$1}"
)
policy_hash_file=/var/lib/tailscale/nix-dotfiles-selinux-policy.sha256

policy_installed=0
if semodule -l 2>/dev/null | awk "{print \$1}" | grep -qx tailscaled; then
  policy_installed=1
fi

install_policy=0
if ((policy_installed == 0)) || [[ ! -f $policy_hash_file ]] || [[ $(<"$policy_hash_file") != "$policy_hash" ]]; then
  install_policy=1
fi

dropin_dir=/etc/systemd/system/tailscaled.service.d
dropin_file=$dropin_dir/10-selinux-context.conf
printf -v desired_dropin "%s\n%s" "[Service]" "SELinuxContext=system_u:system_r:tailscaled_t:s0"

tailscaled_service_context() {
  local main_pid

  main_pid=$(systemctl show -P MainPID tailscaled 2>/dev/null || true)
  if [[ -n $main_pid && $main_pid != 0 ]]; then
    ps -p "$main_pid" -o label= 2>/dev/null | awk "NR == 1 { print; exit }"
  fi
}

tailscale_ssh_sessions_active() {
  local main_pid

  main_pid=$(systemctl show -P MainPID tailscaled 2>/dev/null || true)
  if [[ -z $main_pid || $main_pid == 0 ]]; then
    return 1
  fi

  pgrep -P "$main_pid" -f "tailscaled be-child ssh" >/dev/null 2>&1
}

install_dropin=0
if [[ ! -f $dropin_file ]] || [[ $(<"$dropin_file") != "$desired_dropin" ]]; then
  install_dropin=1
fi

if ((install_policy || install_dropin)) \
  && [[ ${NIX_DOTFILES_TAILSCALE_ALLOW_LIVE_RELOAD:-0} != 1 ]] \
  && tailscale_ssh_sessions_active; then
  printf "%s\n" "tailscale-bluefin: active Tailscale SSH session detected; deferring SELinux policy/drop-in changes to avoid interrupting it" >&2
  printf "%s\n" "tailscale-bluefin: rerun locally, after disconnecting SSH, or set NIX_DOTFILES_TAILSCALE_ALLOW_LIVE_RELOAD=1 to force it" >&2
  exit 0
fi

if ((install_policy)); then
  build_dir=$(mktemp -d)
  trap "rm -rf -- \"$build_dir\"" EXIT
  install -m 0644 "$policy_dir/tailscaled.te" "$policy_dir/tailscaled.fc" "$policy_dir/tailscaled.if" "$build_dir/"
  make -C "$build_dir" -f "$policy_makefile" tailscaled.pp >/dev/null
  semodule -i "$build_dir/tailscaled.pp"

  install -d -m 0700 /var/lib/tailscale
  printf "%s\n" "$policy_hash" >"$policy_hash_file"

  for path in \
    /usr/bin/tailscaled \
    /usr/sbin/tailscaled \
    /usr/lib/systemd/system/tailscaled.service \
    /etc/systemd/system/tailscaled.service; do
    if [[ -e $path ]]; then
      restorecon "$path" || true
    fi
  done

  for path in /var/lib/tailscale /var/cache/tailscale /run/tailscale /var/run/tailscale; do
    if [[ -e $path ]]; then
      restorecon -R "$path" || true
    fi
  done
fi

if ((install_dropin)); then
  install -d -m 0755 "$dropin_dir"
  printf "%s\n" "$desired_dropin" >"$dropin_file"
  systemctl daemon-reload
fi

current_context=$(tailscaled_service_context)
restart_required=0
if ! systemctl is-active --quiet tailscaled; then
  restart_required=1
elif ((install_dropin)); then
  restart_required=1
elif [[ $current_context != system_u:system_r:tailscaled_t:s0 ]]; then
  restart_required=1
fi

if ((restart_required)) \
  && [[ ${NIX_DOTFILES_TAILSCALE_ALLOW_LIVE_RELOAD:-0} != 1 ]] \
  && tailscale_ssh_sessions_active; then
  printf "%s\n" "tailscale-bluefin: active Tailscale SSH session detected; deferring tailscaled restart to avoid interrupting it" >&2
  printf "%s\n" "tailscale-bluefin: rerun locally, after disconnecting SSH, or set NIX_DOTFILES_TAILSCALE_ALLOW_LIVE_RELOAD=1 to force it" >&2
  exit 0
fi

if ((restart_required)) && ! systemctl restart tailscaled; then
  rm -f /etc/systemd/system/tailscaled.service.d/10-selinux-context.conf
  systemctl daemon-reload
  systemctl reset-failed tailscaled || true
  systemctl start tailscaled || true
  die "tailscale-bluefin: confined tailscaled restart failed; removed SELinuxContext drop-in and restarted the unconfined service"
fi

current_context=$(tailscaled_service_context)
if [[ $current_context != system_u:system_r:tailscaled_t:s0 ]]; then
  die "tailscale-bluefin: tailscaled is not running in the expected SELinux context; got: ${current_context:-not running}"
fi
'

run_host_bash "$install_tailscale_selinux_policy" "$policy_dir"

if ! host_has_command tailscale; then
  printf '%s\n' 'tailscale-bluefin: tailscale is not available; add it to the Spectrum image' >&2
  exit 0
fi

tailscale_ready=0
for _ in {1..10}; do
  if run_host_user tailscale status >/dev/null 2>&1 || run_host tailscale status >/dev/null 2>&1; then
    tailscale_ready=1
    break
  fi
  sleep 1
done

if ((tailscale_ready)); then
  if ! run_host_user tailscale set --auto-update=false >/dev/null 2>&1 \
    && ! run_host tailscale set --auto-update=false >/dev/null 2>&1; then
    printf '%s\n' 'tailscale-bluefin: could not disable Tailscale auto-update; keep updates managed by the Spectrum image' >&2
  fi
else
  printf '%s\n' 'tailscale-bluefin: tailscale is installed but not authenticated; run tailscale up on this host' >&2
fi

run_host_bash '
if command -v getenforce >/dev/null 2>&1 \
  && [[ $(getenforce 2>/dev/null || true) == Enforcing ]] \
  && command -v tailscale >/dev/null 2>&1 \
  && tailscale debug prefs 2>/dev/null | grep -q "\"RunSSH\": true"; then
  main_pid=$(systemctl show -P MainPID tailscaled 2>/dev/null || true)
  context=
  if [[ -n $main_pid && $main_pid != 0 ]]; then
    context=$(ps -p "$main_pid" -o label= 2>/dev/null | awk "NR == 1 { print; exit }")
  fi

  if [[ $context != system_u:system_r:tailscaled_t:s0 ]]; then
    die "tailscale-bluefin: Tailscale SSH is enabled under enforcing SELinux, but tailscaled is running as ${context:-not running}"
  fi

  printf "%s\n" "tailscale-bluefin: Tailscale SSH SELinux policy is installed; tailscale status may still show the upstream generic SELinux warning" >&2
fi
'
