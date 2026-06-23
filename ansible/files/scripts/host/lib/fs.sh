# shellcheck shell=bash

if [[ ${NIX_DOTFILES_HOST_LIB_FS_SOURCED:-0} == 1 ]]; then
  return 0
fi
NIX_DOTFILES_HOST_LIB_FS_SOURCED=1

host_lib_dir=${BASH_SOURCE[0]%/*}
# shellcheck disable=SC1091
source -p "$host_lib_dir" paths.sh

remove_path() {
  local path=${1:?path is required}

  require_safe_path "$path"
  require_command rm
  rm -rf -- "$path"
}

ensure_dir() {
  local dir=${1:?directory path is required}

  require_safe_path "$dir"
  require_command mkdir
  mkdir -p -- "$dir"
}

fresh_dir() {
  local dir=${1:?directory path is required}

  remove_path "$dir"
  ensure_dir "$dir"
}

direct_child_paths_into() {
  local -n paths_ref=${1:?path array variable is required}
  local dir=${2:?directory path is required}
  local GLOBIGNORE='' GLOBSORT=none
  local noglob_restore
  local shopt_restore

  case $- in
  *f*) noglob_restore='set -f' ;;
  *) noglob_restore='set +f' ;;
  esac

  shopt_restore=$(shopt -p dotglob failglob nullglob || :)
  set +f
  shopt -s dotglob nullglob
  shopt -u failglob
  # shellcheck disable=SC2034
  paths_ref=("$dir"/*)
  eval "$shopt_restore"
  eval "$noglob_restore"
}

direct_child_dirs_into() {
  local -n dirs_ref=${1:?directory array variable is required}
  local dir=${2:?directory path is required}
  local -a entries=()
  local entry

  direct_child_paths_into entries "$dir"
  dirs_ref=()
  for entry in "${entries[@]}"; do
    if [[ -d $entry ]]; then
      dirs_ref+=("$entry")
    fi
  done
  dirs_ref=("${dirs_ref[@]%/}")
}

recursive_files_by_extension_into() {
  local files_var=${1:?file array variable is required}
  local -n files_ref=$files_var
  local root=${2:?root directory is required}
  shift 2
  local -a extensions=("$@")
  # shellcheck disable=SC2034
  local -A visited_dirs=()

  files_ref=()
  if ((${#extensions[@]} == 0)); then
    die 'at least one file extension is required'
  fi
  if [[ ! -d $root ]]; then
    return
  fi

  _recursive_files_by_extension_walk "$files_var" visited_dirs "$root" "${extensions[@]}"
}

_recursive_files_by_extension_walk() {
  local files_var=${1:?file array variable is required}
  local visited_dirs_var=${2:?visited directory map variable is required}
  # shellcheck disable=SC2178
  local -n files_ref=$files_var
  local -n visited_dirs_ref=$visited_dirs_var
  local dir=${3:?directory path is required}
  shift 3
  local -a extensions=("$@")
  local physical_dir
  local -a entries=()
  local entry extension candidate

  if ! physical_dir=$(cd -P -- "$dir" 2>/dev/null && pwd -P); then
    return
  fi
  if [[ ${visited_dirs_ref["$physical_dir"]+set} ]]; then
    return
  fi
  visited_dirs_ref["$physical_dir"]=1

  direct_child_paths_into entries "$dir"

  for entry in "${entries[@]}"; do
    if [[ -d $entry ]]; then
      _recursive_files_by_extension_walk "$files_var" "$visited_dirs_var" "$entry" "${extensions[@]}"
      continue
    fi
    if [[ ! -f $entry ]]; then
      continue
    fi

    candidate=${entry##*/}
    extension=${candidate##*.}
    if [[ $candidate == "$extension" ]]; then
      continue
    fi
    extension=${extension,,}
    for candidate in "${extensions[@]}"; do
      if [[ $extension == "${candidate,,}" ]]; then
        files_ref+=("$entry")
        break
      fi
    done
  done
}
