#!/usr/bin/env bash
set -euo pipefail

app_id=${SUSHI_PREVIEW_APP_ID:-org.gnome.NautilusPreviewer}
source_rev=${SUSHI_PREVIEW_REV:-d367b6d5f538cd33e53743847a34e5be94e2b22b}
source_url=${SUSHI_PREVIEW_REPO:-https://github.com/GNOME/sushi.git}

if [[ -n ${NIX_DOTFILES_SUSHI_PATCH_DIR:-} ]]; then
  patch_dir=$NIX_DOTFILES_SUSHI_PATCH_DIR
else
  script_dir=$(cd -P -- "${BASH_SOURCE[0]%/*}" && pwd -P)
  patch_dir=$script_dir/patches
fi

cache_root=${XDG_CACHE_HOME:-$HOME/.cache}/nix-dotfiles/sushi-preview-flatpak
source_dir=$cache_root/source
build_dir=$cache_root/build
stamp_dir=${XDG_STATE_HOME:-$HOME/.local/state}/nix-dotfiles
stamp_file=$stamp_dir/sushi-preview-flatpak.stamp

require_command() {
  local command_name=${1:?command name is required}
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf '%s\n' "required command is not available: $command_name" >&2
    exit 1
  fi
}

require_command awk
require_command flatpak
require_command git
require_command patch
require_command sha256sum

if [[ ! -d $patch_dir ]]; then
  printf '%s\n' "patch directory does not exist: $patch_dir" >&2
  exit 1
fi

patch_hash=$(
  shopt -s nullglob
  patches=("$patch_dir"/*.patch)
  if ((${#patches[@]} == 0)); then
    printf '%s\n' "no Sushi patches found in $patch_dir" >&2
    exit 1
  fi
  sha256sum "${patches[@]}" | sha256sum | awk '{ print $1 }'
)
stamp="rev=$source_rev patch_hash=$patch_hash app_id=$app_id"

flatpak override --user --env=GDK_GL=gles "$app_id" >/dev/null 2>&1 || true

if [[ -f $stamp_file ]] && [[ $(<"$stamp_file") == "$stamp" ]] && flatpak info --user "$app_id" >/dev/null 2>&1; then
  printf '%s\n' "$app_id is already installed from $source_rev with the current patch set"
  exit 0
fi

mkdir -p "$cache_root" "$stamp_dir"

flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak remote-add --user --if-not-exists gnome-nightly https://nightly.gnome.org/gnome-nightly.flatpakrepo

flatpak install --user --noninteractive flathub org.flatpak.Builder
flatpak install --user --noninteractive gnome-nightly org.gnome.Platform//master org.gnome.Sdk//master
flatpak install --user --noninteractive flathub org.freedesktop.Sdk.Extension.rust-stable//25.08

if [[ -d $source_dir/.git ]]; then
  git -C "$source_dir" fetch --tags --prune origin
else
  rm -rf "$source_dir"
  git clone "$source_url" "$source_dir"
fi

git -C "$source_dir" checkout --force "$source_rev"
git -C "$source_dir" clean -fdx

for patch_file in "$patch_dir"/*.patch; do
  git -C "$source_dir" apply "$patch_file"
done

(
  cd "$source_dir"
  flatpak run org.flatpak.Builder --user --install --force-clean "$build_dir" flatpak/org.gnome.NautilusPreviewer.json
)

flatpak override --user --env=GDK_GL=gles "$app_id"
flatpak kill "$app_id" >/dev/null 2>&1 || true
if command -v nautilus >/dev/null 2>&1; then
  nautilus -q >/dev/null 2>&1 || true
fi

printf '%s\n' "$stamp" >"$stamp_file"
printf '%s\n' "installed patched $app_id from $source_rev"
