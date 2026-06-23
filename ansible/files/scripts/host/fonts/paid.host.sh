# shellcheck shell=bash

require_commands install rm

home=$1
src="$home/.local/share/nix-dotfiles/immutable/host-fonts/paid"
dest="/usr/local/share/fonts/nix-dotfiles-paid"

require_safe_path "$dest"
remove_path "$dest"
ensure_dir "$dest"
if [[ -d $src ]]; then
  declare -a copied_paths=()
  declare path rel target noglob_restore shopt_restore
  GLOBIGNORE="" GLOBSORT=none
  case $- in
  *f*) noglob_restore="set -f" ;;
  *) noglob_restore="set +f" ;;
  esac
  shopt_restore=$(shopt -p dotglob failglob globstar nullglob || :)
  set +f
  shopt -s dotglob globstar nullglob
  shopt -u failglob
  copied_paths=("$src"/**)
  eval "$shopt_restore"
  eval "$noglob_restore"
  for path in "${copied_paths[@]}"; do
    rel=${path#"$src"/}
    target="$dest/$rel"
    if [[ -d $path ]]; then
      install -d -m 0755 "$target"
    elif [[ -f $path ]]; then
      install -D -m 0644 "$path" "$target"
    fi
  done
fi
