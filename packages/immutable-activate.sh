#!/usr/bin/env bash
# shellcheck shell=bash
# Build and activate the nix-dotfiles immutable Linux user profile.
set -euo pipefail
shopt -s inherit_errexit array_expand_once globskipdots

readonly runtime_path="@runtimePath@"
readonly marker="# nix-dotfiles: immutable-wrapper"

usage() {
  cat <<'EOF'
Usage: immutable-activate [options]

Build and activate the nix-dotfiles immutable Linux user profile.

Options:
  --flake PATH          Use PATH as the nix-dotfiles flake checkout.
  --update             Run `nix flake update` before activation.
  --host-update        Also run native host/user package updates when available.
  --host-updater NAME  Select the native updater: auto, none, rpm-ostree, pacman, dnf, or apt.
  --skip-scaffold      Do not run `scaffold install`.
  --help               Show this help.
EOF
}

log_error() {
  printf '%s\n' "immutable-activate: $*" >&2
}

die() {
  local -r message=$1
  local -r status=${2:-1}

  log_error "$message"
  exit "$status"
}

setup_runtime_path() {
  if [[ "$runtime_path" != "@runtimePath@" ]]; then
    export PATH="$runtime_path:$PATH"
  fi
}

is_wrapper() {
  [[ -f "$1" ]] && grep -Fqx "$marker" "$1" 2>/dev/null
}

os_release_words() {
  local key value id="" id_like=""

  if [[ -r /etc/os-release ]]; then
    while IFS='=' read -r key value; do
      value="${value%\"}"
      value="${value#\"}"
      case "$key" in
      ID)
        id="$value"
        ;;
      ID_LIKE)
        id_like="$value"
        ;;
      esac
    done </etc/os-release
  fi

  printf '%s %s\n' "$id" "$id_like"
}

detect_host_updater() {
  local host_updater=$1
  local -A valid_updater=(
    [apt]=1
    [dnf]=1
    [none]=1
    [pacman]=1
    ["rpm-ostree"]=1
  )

  case "$host_updater" in
  auto)
    ;;
  *)
    if [[ -v "valid_updater[$host_updater]" ]]; then
      printf '%s\n' "$host_updater"
      return
    fi

    log_error "unknown host updater: $host_updater"
    return 2
    ;;
  esac

  if [[ -e /run/ostree-booted ]]; then
    printf '%s\n' "rpm-ostree"
    return
  fi

  local -A os_updater=(
    [arch]=pacman
    [centos]=dnf
    [debian]=apt
    [fedora]=dnf
    [rhel]=dnf
    [ubuntu]=apt
  )
  local os_word

  for os_word in $(os_release_words); do
    if [[ -v "os_updater[$os_word]" ]]; then
      printf '%s\n' "${os_updater[$os_word]}"
      return
    fi
  done

  printf '%s\n' "none"
}

run_native_updates() {
  local host_updater=$1
  local resolved_updater

  resolved_updater=${ detect_host_updater "$host_updater";}

  case "$resolved_updater" in
  none)
    ;;
  rpm-ostree)
    rpm-ostree upgrade
    ;;
  pacman)
    sudo pacman -Syu
    ;;
  dnf)
    sudo dnf upgrade -y
    ;;
  apt)
    sudo apt-get update
    sudo apt-get upgrade -y
    ;;
  esac

  if command -v flatpak >/dev/null 2>&1; then
    flatpak update -y
  fi

  if command -v brew >/dev/null 2>&1; then
    brew update
    brew upgrade
  fi
}

install_wrapper() {
  local profile=$1
  local wrapper_dir=$2
  local source_bin=$3
  local owned_now=$4
  local name dest tmp quoted_target

  name=${source_bin##*/}
  dest="$wrapper_dir/$name"
  tmp="$(mktemp "$wrapper_dir/.nix-dotfiles-$name.XXXXXX")"
  printf -v quoted_target '%#q' "$profile/bin/$name"

  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' "$marker"
    printf 'exec %s "$@"\n' "$quoted_target"
  } >"$tmp"
  chmod 0755 "$tmp"

  if [[ -e "$dest" || -L "$dest" ]]; then
    if is_wrapper "$dest"; then
      mv -f "$tmp" "$dest"
    else
      rm -f "$tmp"
      log_error "leaving existing non-managed command alone: $dest"
      return
    fi
  else
    mv "$tmp" "$dest"
  fi

  printf '%s\0' "$dest" >>"$owned_now"
}

remove_stale_wrappers() {
  local wrapper_dir=$1
  local owned_now=$2
  local candidate
  local -a candidates=()

  mapfile -d '' -t candidates < <(find "$wrapper_dir" -maxdepth 1 -type f -print0)

  for candidate in "${candidates[@]}"; do
    if is_wrapper "$candidate" && ! grep -Fzxq -- "$candidate" "$owned_now"; then
      rm -f "$candidate"
    fi
  done
}

default_flake() {
  local candidate
  local -a candidates=(
    "$PWD"
    "/etc/nixos"
  )

  if [[ -v HOME && -n "$HOME" ]]; then
    candidates+=(
      "$HOME/Developer/nix-dotfiles"
      "$HOME/nix-dotfiles"
    )
  fi

  for candidate in "${candidates[@]}"; do
    if [[ -f "$candidate/flake.nix" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done
}

main() {
  setup_runtime_path

  local flake="${NIX_DOTFILES_FLAKE:-}"
  local run_update=0
  local run_host_update=0
  local host_updater="${NIX_DOTFILES_HOST_UPDATER:-auto}"
  local run_scaffold=1

  while (($# > 0)); do
    case "$1" in
    --flake)
      (($# >= 2)) || die "--flake requires a path" 2
      flake="$2"
      shift 2
      ;;
    --update)
      run_update=1
      shift
      ;;
    --host-update)
      run_host_update=1
      shift
      ;;
    --host-updater)
      (($# >= 2)) || die "--host-updater requires a value" 2
      host_updater="$2"
      shift 2
      ;;
    --skip-scaffold)
      run_scaffold=0
      shift
      ;;
    --help | -h)
      usage
      return
      ;;
    *)
      log_error "unknown option: $1"
      usage >&2
      return 2
      ;;
    esac
  done

  [[ "$(uname -s)" == "Linux" ]] \
    || die "this entry point is only for portable Linux hosts"

  if [[ -z "$flake" ]]; then
    flake=${ default_flake;}
  fi

  if [[ -z "$flake" ]]; then
    log_error "could not find a nix-dotfiles flake checkout"
    printf '%s\n' "set NIX_DOTFILES_FLAKE or pass --flake PATH" >&2
    return 1
  fi

  if [[ -d "$flake" ]]; then
    flake="$(cd -P -- "$flake" && pwd)"
  fi

  local data_home="${XDG_DATA_HOME:-${HOME:?HOME must be set}/.local/share}"
  local bin_home="${XDG_BIN_HOME:-${HOME:?HOME must be set}/.local/bin}"
  local profile_root="$data_home/nix-dotfiles/immutable"
  local profile="$profile_root/profile"
  local wrapper_dir="$bin_home"

  mkdir -p "$profile_root" "$wrapper_dir"

  if ((run_host_update == 1)); then
    run_native_updates "$host_updater"
  fi

  if ((run_update == 1)); then
    nix flake update --flake "$flake"
  fi

  nix build --profile "$profile" "$flake#immutable-profile"

  if [[ ! -d "$profile/bin" ]]; then
    die "immutable profile has no bin directory: $profile/bin"
  fi

  local owned_now source_bin
  local -a source_bins=()
  owned_now="$(mktemp)"
  trap 'rm -f "$owned_now"' EXIT

  mapfile -d '' -t source_bins < <(find "$profile/bin" -maxdepth 1 \( -type f -o -type l \) -print0 | sort -z)

  for source_bin in "${source_bins[@]}"; do
    [[ -x "$source_bin" ]] || continue
    install_wrapper "$profile" "$wrapper_dir" "$source_bin" "$owned_now"
  done

  remove_stale_wrappers "$wrapper_dir" "$owned_now"

  if ((run_scaffold == 1)); then
    scaffold install
  fi

  printf '%s\n' "immutable-activate: activated $flake#immutable-profile"
  printf '%s\n' "immutable-activate: wrappers managed in $wrapper_dir"
}

main "$@"
