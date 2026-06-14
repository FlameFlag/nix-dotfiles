#!/bin/bash
# shellcheck shell=bash
# Build and activate the nix-dotfiles immutable Linux user profile.
set -euo pipefail
shopt -s inherit_errexit array_expand_once globskipdots

readonly runtime_path="@runtimePath@"
readonly distrobox_manifest="@distroboxManifest@"
readonly marker="# nix-dotfiles: immutable-wrapper"
readonly NIX_CONTAINER_NAME="fedora-nix"
readonly LEGACY_NIX_CONTAINER_NAME="arch-nix"
readonly CONTAINER_SYSTEM_PATH="/usr/local/sbin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"

usage() {
  cat <<'EOF'
Usage: immutable-activate [options]

Build and activate the nix-dotfiles immutable Linux user profile.

Options:
  --flake PATH          Use PATH as the nix-dotfiles flake checkout.
  --backend NAME        Select activation backend: auto, host, or container.
  --reset-containers   With --backend container, delete managed Distrobox containers first.
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

require_command() {
  local name=$1

  command -v "$name" >/dev/null 2>&1 || die "missing required command: $name"
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

install_host_wrapper() {
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
    printf '%s\n' '#!/bin/sh'
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

link_scaffold_extension() {
  local flake=$1
  local name=$2
  local source="$flake/scaffold/$name"
  local dest="$flake/.scaffold/extensions/$name"
  local relative_source="../../scaffold/$name"

  [[ -d "$source" ]] || die "missing Scaffold extension source: $source"

  if [[ -L "$dest" ]]; then
    ln -sfn "$relative_source" "$dest"
  elif [[ -e "$dest" ]]; then
    die "refusing to replace non-symlink Scaffold extension path: $dest"
  else
    ln -s "$relative_source" "$dest"
  fi
}

ensure_scaffold_extensions() {
  local flake=$1

  mkdir -p "$flake/.scaffold/extensions"
  link_scaffold_extension "$flake" entries
  link_scaffold_extension "$flake" installers
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

distrobox_enter() {
  local name=$1
  shift

  distrobox enter --name "$name" -- "$@"
}

resolve_distrobox_manifest() {
  local manifest=$distrobox_manifest

  if [[ "$manifest" == "@distroboxManifest@" ]]; then
    manifest="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/immutable-distrobox.ini"
  fi

  [[ -f "$manifest" ]] || die "missing Distrobox manifest: $manifest"
  printf '%s\n' "$manifest"
}

profile_container_path() {
  printf '%s:%s:%s:%s:%s\n' \
    "$HOME/.local/bin" \
    "$HOME/.cache/.bun/bin" \
    "$HOME/.cargo/bin" \
    "$HOME/.nix-profile/bin" \
    "$CONTAINER_SYSTEM_PATH"
}

nix_container_path() {
  printf '%s:%s:%s\n' "$HOME/.nix-profile/bin" "/nix/var/nix/profiles/default/bin" "$CONTAINER_SYSTEM_PATH"
}

ensure_nix_container() {
  local manifest=$1

  distrobox assemble create --file "$manifest" --name "$NIX_CONTAINER_NAME"

  if ! distrobox_enter "$NIX_CONTAINER_NAME" env "PATH=$(nix_container_path)" nix --version >/dev/null 2>&1; then
    die "managed Distrobox container has no working Nix; rerun with --reset-containers"
  fi
}

export_profile_container_bins() {
  local export_dir=$1
  local launcher_dir=$2
  local -a env_args=(
    "NIX_DOTFILES_CONTAINER_PATH=$(profile_container_path)"
    "NIX_DOTFILES_EXPORT_DIR=$export_dir"
    "NIX_DOTFILES_LAUNCHER_DIR=$launcher_dir"
  )

  distrobox_enter "$NIX_CONTAINER_NAME" env "${env_args[@]}" sh -s <<'CONTAINER_SCRIPT'
set -eu

profile_bin="$HOME/.nix-profile/bin"
if [ ! -d "$profile_bin" ]; then
  exit 0
fi

rm -rf "$NIX_DOTFILES_LAUNCHER_DIR"
mkdir -p "$NIX_DOTFILES_LAUNCHER_DIR"

real_profile_bin=$(readlink -f "$profile_bin")
find "$real_profile_bin" -maxdepth 1 \( -type f -o -type l \) -perm /111 -print | sort | while IFS= read -r source; do
  name=${source##*/}
  launcher="$NIX_DOTFILES_LAUNCHER_DIR/$name"
  {
    printf "%s\n" "#!/bin/sh"
    printf "export PATH=\"%s\"\n" "$NIX_DOTFILES_CONTAINER_PATH"
    printf "exec \"%s\" \"\$@\"\n" "$profile_bin/$name"
  } >"$launcher"
  chmod 0755 "$launcher"
  distrobox-export --bin "$launcher" --export-path "$NIX_DOTFILES_EXPORT_DIR" >/dev/null
done
CONTAINER_SCRIPT
}

remove_legacy_container_wrappers() {
  local wrapper_dir=$1
  local candidate
  local -a candidates=()

  [[ -d "$wrapper_dir" ]] || return
  mapfile -d '' -t candidates < <(find "$wrapper_dir" -maxdepth 1 -type f -print0)

  for candidate in "${candidates[@]}"; do
    if is_wrapper "$candidate" && grep -Eq '^# group: (arch-nix|arch-dev)$' "$candidate"; then
      rm -f "$candidate"
    fi
  done
}

reset_managed_containers() {
  local manifest=$1

  distrobox assemble rm --file "$manifest" --name "$NIX_CONTAINER_NAME" || true
  distrobox rm --force "$LEGACY_NIX_CONTAINER_NAME" || true
}

activate_host_profile() {
  local flake=$1
  local run_update=$2
  local run_scaffold=$3
  local data_home="${XDG_DATA_HOME:-${HOME:?HOME must be set}/.local/share}"
  local bin_home="${XDG_BIN_HOME:-${HOME:?HOME must be set}/.local/bin}"
  local profile_root="$data_home/nix-dotfiles/immutable"
  local profile="$profile_root/profile"
  local wrapper_dir="$bin_home"
  local owned_now cleanup source_bin
  local -a source_bins=()

  mkdir -p "$profile_root" "$wrapper_dir"

  if ((run_update == 1)); then
    nix flake update --flake "$flake"
  fi

  nix build --profile "$profile" "$flake#immutable-profile"

  if [[ ! -d "$profile/bin" ]]; then
    die "immutable profile has no bin directory: $profile/bin"
  fi

  owned_now="$(mktemp)"
  printf -v cleanup 'rm -f -- %q' "$owned_now"
  # shellcheck disable=SC2064
  trap "$cleanup" RETURN

  mapfile -d '' -t source_bins < <(find "$profile/bin" -maxdepth 1 \( -type f -o -type l \) -print0 | sort -z)

  for source_bin in "${source_bins[@]}"; do
    [[ -x "$source_bin" ]] || continue
    install_host_wrapper "$profile" "$wrapper_dir" "$source_bin" "$owned_now"
  done

  remove_stale_wrappers "$wrapper_dir" "$owned_now"

  if ((run_scaffold == 1)); then
    ensure_scaffold_extensions "$flake"
    scaffold --catalog "$flake/scaffold.scm" install
  fi

  printf '%s\n' "immutable-activate: activated $flake#immutable-profile"
  printf '%s\n' "immutable-activate: wrappers managed in $wrapper_dir"
}

activate_container_profile() {
  local flake=$1
  local run_update=$2
  local run_scaffold=$3
  local reset=$4
  local bin_home="${XDG_BIN_HOME:-${HOME:?HOME must be set}/.local/bin}"
  local export_root="${HOME:?HOME must be set}/.local/share/nix-dotfiles/immutable"
  local export_dir="$export_root/bin"
  local launcher_root="$export_root/container-launchers"
  local manifest
  local -a nix_env_args=(
    "PATH=$(nix_container_path)"
  )
  local -a nix_flake_args=(
    nix
    --extra-experimental-features
    "nix-command flakes"
  )

  require_command distrobox

  mkdir -p "$bin_home" "$export_dir" "$launcher_root"
  manifest=$(resolve_distrobox_manifest)

  if ((reset == 1)); then
    reset_managed_containers "$manifest"
  fi

  ensure_nix_container "$manifest"

  if ((run_update == 1)); then
    distrobox_enter "$NIX_CONTAINER_NAME" env "${nix_env_args[@]}" \
      "${nix_flake_args[@]}" flake update --flake "$flake"
  fi

  distrobox_enter "$NIX_CONTAINER_NAME" env "${nix_env_args[@]}" \
    "${nix_flake_args[@]}" profile remove immutable-profile >/dev/null 2>&1 || true
  distrobox_enter "$NIX_CONTAINER_NAME" env "${nix_env_args[@]}" \
    "${nix_flake_args[@]}" profile install "path:$flake#immutable-profile"

  rm -rf "$export_dir"
  mkdir -p "$export_dir"
  export_profile_container_bins "$export_dir" "$launcher_root/$NIX_CONTAINER_NAME"
  remove_legacy_container_wrappers "$bin_home"

  if ((run_scaffold == 1)); then
    ensure_scaffold_extensions "$flake"
    "$export_dir/scaffold" --catalog "$flake/scaffold.scm" install
  fi

  printf '%s\n' "immutable-activate: activated path:$flake#immutable-profile through $NIX_CONTAINER_NAME"
  printf '%s\n' "immutable-activate: Distrobox exports managed in $export_dir"
}

main() {
  setup_runtime_path

  local flake="${NIX_DOTFILES_FLAKE:-}"
  local backend="${NIX_DOTFILES_IMMUTABLE_BACKEND:-auto}"
  local run_update=0
  local run_host_update=0
  local host_updater="${NIX_DOTFILES_HOST_UPDATER:-auto}"
  local run_scaffold=1
  local reset_containers=0

  while (($# > 0)); do
    case "$1" in
    --flake)
      (($# >= 2)) || die "--flake requires a path" 2
      flake="$2"
      shift 2
      ;;
    --backend)
      (($# >= 2)) || die "--backend requires a value" 2
      backend="$2"
      shift 2
      ;;
    --reset-containers)
      reset_containers=1
      shift
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

  if ((run_host_update == 1)); then
    run_native_updates "$host_updater"
  fi

  case "$backend" in
  auto)
    if command -v nix >/dev/null 2>&1; then
      backend=host
    else
      backend=container
    fi
    ;;
  host | container)
    ;;
  *)
    die "unknown backend: $backend" 2
    ;;
  esac

  case "$backend" in
  host)
    activate_host_profile "$flake" "$run_update" "$run_scaffold"
    ;;
  container)
    activate_container_profile "$flake" "$run_update" "$run_scaffold" "$reset_containers"
    ;;
  esac
}

main "$@"
