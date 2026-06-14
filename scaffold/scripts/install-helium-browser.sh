#!/usr/bin/env bash
# shellcheck shell=bash
set -Eeuo pipefail
IFS=$'\n\t'

if (($# != 4)); then
  printf 'usage: %s <macos|linux> <cache-dir> <bin-dir> <flags>\n' "${0##*/}" >&2
  exit 64
fi

readonly mode=$1
readonly root=$2
readonly bin_dir=$3
readonly flags=$4
script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
readonly script_dir
readonly settings_path="${script_dir}/../data/helium-extension-settings.json"
readonly settings_applier_src="${script_dir}/../../packages/helium-extension-settings-applier"
readonly secrets_path="${script_dir}/../../secrets/secrets.yaml"
readonly chrome_store_update_url="https://clients2.google.com/service/update2/crx"
readonly twp_id="bolggfoncklhniejomgplkjcllmnonbh"
readonly twp_version="10.1.1.0"
readonly twp_url="https://github.com/FilipePS/Traduzir-paginas-web/releases/download/v10.1.1.0/TWP_10.1.1.0_Chromium.crx"
readonly cookie_autodelete_id="hebmefdjnehapihcomeennjpdjghcpdn"
readonly cookie_autodelete_version="3.8.2"
readonly cookie_autodelete_url="https://github.com/Cookie-AutoDelete/Cookie-AutoDelete/releases/download/v3.8.2/Cookie-AutoDelete_v3.8.2_Chrome.zip"
readonly -a chrome_store_extension_ids=(
  "aeblfdkhhhdcdjpifhhbdiojplfjncoa" # 1Password
  "lnjaiaapbakfhlbjenjkhffcdpoompki" # Catppuccin for Web File Explorer Icons
  "ponfpcnoihfmfllpaingbgckeeldkhle" # Enhancer for YouTube
  "pobhoodpcipjmedfenaigbeloiidbflp" # Minimal Theme for Twitta
  "ldgfbffkinooeloadekpmfoklnobpien" # Raindrop
  "mnjggcdmjocbbbhaepdhchncahnbgone" # SponsorBlock for YouTube
  "hlepfoohegkhhmjieoechaddaejaokhf" # Refined GitHub
)

extra_wrapper_flags=()

latest_version() {
  local latest_url
  local version

  latest_url=$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/imputnet/helium-macos/releases/latest")
  version=${latest_url##*/}

  if [[ -z $version || $version == releases ]]; then
    printf '%s\n' "helium-browser: failed to discover latest version" >&2
    exit 1
  fi

  printf '%s\n' "$version"
}

sed_replacement_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//&/\\&}
  value=${value//|/\\|}
  printf '%s\n' "$value"
}

json_string_escape() {
  local value=$1
  value=${value//\\/\\\\}
  value=${value//\"/\\\"}
  value=${value//$'\n'/\\n}
  value=${value//$'\r'/\\r}
  value=${value//$'\t'/\\t}
  printf '%s\n' "$value"
}

write_wrapper() {
  local target=$1
  local launcher=$2
  local -a flag_args=()

  if [[ -n $flags ]]; then
    IFS=' ' read -r -a flag_args <<<"$flags"
  fi

  {
    printf '#!/usr/bin/env bash\n'
    printf 'set -Eeuo pipefail\n'
    printf 'exec %q' "$launcher"
    if ((${#flag_args[@]} > 0)); then
      printf ' %q' "${flag_args[@]}"
    fi
    if ((${#extra_wrapper_flags[@]} > 0)); then
      printf ' %q' "${extra_wrapper_flags[@]}"
    fi
    printf ' "$@"\n'
  } >"$target"

  chmod 0755 "$target"
}

external_extension_dirs() {
  case $mode in
  macos)
    printf '%s\n' \
      "${HOME}/Library/Application Support/net.imput.helium/External Extensions" \
      "${HOME}/Library/Application Support/Helium/External Extensions"
    ;;
  linux)
    printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/net.imput.helium/External Extensions"
    ;;
  esac
}

write_external_crx_json() {
  local dir=$1
  local id=$2
  local crx_path=$3
  local version=$4
  local escaped_path
  local escaped_version

  escaped_path=$(json_string_escape "$crx_path")
  escaped_version=$(json_string_escape "$version")

  cat >"${dir}/${id}.json" <<EOF
{
  "external_crx": "${escaped_path}",
  "external_version": "${escaped_version}"
}
EOF
}

write_external_update_json() {
  local dir=$1
  local id=$2
  local escaped_update_url

  escaped_update_url=$(json_string_escape "$chrome_store_update_url")

  cat >"${dir}/${id}.json" <<EOF
{
  "external_update_url": "${escaped_update_url}"
}
EOF
}

install_extensions() {
  local crx_dir="${root}/extensions/crx"
  local unpacked_dir="${root}/extensions/unpacked"
  local twp_crx="${crx_dir}/${twp_id}.crx"
  local cookie_zip="${root}/extensions/${cookie_autodelete_id}-${cookie_autodelete_version}.zip"
  local cookie_dir="${unpacked_dir}/${cookie_autodelete_id}"
  local external_dir
  local chrome_store_extension_id

  mkdir -p "$crx_dir" "$unpacked_dir"

  curl -fsSL --retry 3 -o "$twp_crx" "$twp_url"
  curl -fsSL --retry 3 -o "$cookie_zip" "$cookie_autodelete_url"

  rm -rf "$cookie_dir"
  mkdir -p "$cookie_dir"
  unzip -q "$cookie_zip" -d "$cookie_dir"

  while IFS= read -r external_dir; do
    mkdir -p "$external_dir"
    write_external_crx_json "$external_dir" "$twp_id" "$twp_crx" "$twp_version"

    for chrome_store_extension_id in "${chrome_store_extension_ids[@]}"; do
      write_external_update_json "$external_dir" "$chrome_store_extension_id"
    done
  done < <(external_extension_dirs)

  extra_wrapper_flags+=("--load-extension=${cookie_dir}")
}

profile_dir() {
  case $mode in
  macos)
    printf '%s\n' "${HOME}/Library/Application Support/net.imput.helium/Default"
    ;;
  linux)
    printf '%s\n' "${XDG_CONFIG_HOME:-${HOME}/.config}/net.imput.helium/Default"
    ;;
  esac
}

install_settings_applier() {
  local applier_dir="${root}/extension-settings-applier"

  rm -rf "$applier_dir"
  mkdir -p "$applier_dir"
  cp \
    "${settings_applier_src}/bun.lock" \
    "${settings_applier_src}/package.json" \
    "$applier_dir/"
  cp -R "${settings_applier_src}/src" "$applier_dir/"

  bun install --cwd "$applier_dir" --production --frozen-lockfile >&2
  printf '%s\n' "$applier_dir"
}

apply_extension_settings() {
  local applier_dir
  local private_settings_file=""
  local target_profile_dir
  local -a settings_args

  if [[ ! -f $settings_path ]]; then
    printf 'helium-browser: extension settings file is missing: %s\n' "$settings_path" >&2
    return
  fi

  if [[ ! -d $settings_applier_src ]]; then
    printf 'helium-browser: extension settings applier is missing: %s\n' "$settings_applier_src" >&2
    return
  fi

  target_profile_dir=$(profile_dir)
  mkdir -p "$target_profile_dir"
  applier_dir=$(install_settings_applier)
  settings_args=(--settings "$settings_path")

  if [[ -f $secrets_path ]] && command -v sops >/dev/null 2>&1; then
    private_settings_file=$(mktemp "${root}/helium-cookie-settings.XXXXXX.json")
    if sops -d --extract '["helium-cookie-autodelete-settings"]' "$secrets_path" >"$private_settings_file"; then
      settings_args+=(--settings "$private_settings_file")
    else
      rm -f "$private_settings_file"
      private_settings_file=""
      printf '%s\n' "helium-browser: failed to decrypt private Cookie AutoDelete settings; continuing with public settings" >&2
    fi
  fi

  bun "${applier_dir}/src/apply-helium-extension-settings.ts" \
    --profile-dir "$target_profile_dir" \
    "${settings_args[@]}" \
    --gh-token

  if [[ -n $private_settings_file ]]; then
    rm -f "$private_settings_file"
  fi
}

install_macos() {
  local version
  local app_dst
  local dmg
  local mount_dir

  version=$(latest_version)
  app_dst="/Applications/Helium.app"
  dmg="${root}/helium_${version}_arm64-macos.dmg"
  mount_dir="${root}/mount"

  mkdir -p "$root" "$bin_dir"
  curl -fsSL --retry 3 -o "$dmg" \
    "https://github.com/imputnet/helium-macos/releases/download/${version}/helium_${version}_arm64-macos.dmg"

  rm -rf "$mount_dir"
  mkdir -p "$mount_dir"
  hdiutil attach "$dmg" -nobrowse -readonly -mountpoint "$mount_dir"
  HELIUM_MOUNT_DIR=$mount_dir
  trap 'hdiutil detach "$HELIUM_MOUNT_DIR" >/dev/null 2>&1 || true' EXIT

  rm -rf "$app_dst"
  ditto "${mount_dir}/Helium.app" "$app_dst"

  install_extensions
  apply_extension_settings
  write_wrapper "${bin_dir}/helium-browser" "${app_dst}/Contents/MacOS/Helium"
  ln -sfn helium-browser "${bin_dir}/helium"
}

install_linux() {
  local os_id=""
  local os_like=""
  local key
  local value
  local machine_arch
  local helium_arch
  local version
  local archive
  local extract_dir
  local app_dir
  local data_home
  local entry
  local payload=""
  local escaped_exec
  local -a entries

  if [[ -r /etc/os-release ]]; then
    while IFS='=' read -r key value; do
      value=${value%\"}
      value=${value#\"}
      case $key in
      ID) os_id=$value ;;
      ID_LIKE) os_like=$value ;;
      esac
    done </etc/os-release

    if [[ " $os_id $os_like " == *" nixos "* ]]; then
      printf '%s\n' "helium-browser: NixOS host detected; install is managed by the NixOS system closure"
      exit 0
    fi
  fi

  machine_arch=$(uname -m)
  case $machine_arch in
  aarch64 | arm64) helium_arch=arm64 ;;
  x86_64 | amd64) helium_arch=x86_64 ;;
  *)
    printf 'helium-browser: unsupported Linux architecture: %s\n' "$machine_arch" >&2
    exit 1
    ;;
  esac

  version=$(latest_version)
  archive="${root}/helium-${version}-${helium_arch}_linux.tar.xz"
  extract_dir="${root}/extract"
  app_dir="${root}/app"
  data_home="${XDG_DATA_HOME:-${HOME}/.local/share}"

  mkdir -p \
    "$root" \
    "$bin_dir" \
    "${data_home}/applications" \
    "${data_home}/icons/hicolor/256x256/apps"

  curl -fsSL --retry 3 -o "$archive" \
    "https://github.com/imputnet/helium-linux/releases/download/${version}/helium-${version}-${helium_arch}_linux.tar.xz"

  rm -rf "$extract_dir" "$app_dir"
  mkdir -p "$extract_dir" "$app_dir"
  tar -xJf "$archive" -C "$extract_dir"

  shopt -s nullglob
  entries=("${extract_dir}"/*)
  shopt -u nullglob

  for entry in "${entries[@]}"; do
    if [[ -d $entry ]]; then
      payload=$entry
      break
    fi
  done

  if [[ -z $payload ]]; then
    printf '%s\n' "helium-browser: extracted archive did not contain an application directory" >&2
    exit 1
  fi

  cp -R "${payload}/." "$app_dir/"
  rm -f "${app_dir}/libqt5_shim.so"

  install_extensions
  apply_extension_settings
  write_wrapper "${bin_dir}/helium-browser" "${app_dir}/helium-wrapper"
  ln -sfn helium-browser "${bin_dir}/helium"

  if [[ -f ${app_dir}/helium.desktop ]]; then
    escaped_exec=$(sed_replacement_escape "${bin_dir}/helium-browser")
    sed \
      -e "s|^Exec=helium %U|Exec=${escaped_exec} %U|" \
      -e "s|^Exec=helium --incognito|Exec=${escaped_exec} --incognito|" \
      -e "s|^Exec=helium$|Exec=${escaped_exec}|" \
      "${app_dir}/helium.desktop" >"${data_home}/applications/helium-browser.desktop"
  fi

  if [[ -f ${app_dir}/product_logo_256.png ]]; then
    cp "${app_dir}/product_logo_256.png" "${data_home}/icons/hicolor/256x256/apps/helium.png"
  fi

  rm -rf "$extract_dir"
}

case $mode in
macos) install_macos ;;
linux) install_linux ;;
*)
  printf 'helium-browser: unsupported installer mode: %s\n' "$mode" >&2
  exit 1
  ;;
esac
