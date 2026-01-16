#!/usr/bin/env bash
#
# Author: FlameFlag
#

set -euo pipefail

readonly YAZI_CONFIG_DIR="$HOME/.config/yazi"
readonly PLUGINS_DIR="$YAZI_CONFIG_DIR/plugins"
readonly FLAVORS_DIR="$YAZI_CONFIG_DIR/flavors"
readonly YAZI_PLUGINS_REPO="https://github.com/yazi-rs/plugins.git"
TEMP_PLUGINS_DIR=$(mktemp -d)
readonly TEMP_PLUGINS_DIR

cleanup() {
    if [[ -d "$TEMP_PLUGINS_DIR" ]]; then
        rm -rf "$TEMP_PLUGINS_DIR"
    fi
}

is_directory_empty() {
    local dir=$1
    [[ -z "$(find "$dir" -mindepth 1 -print -quit 2>/dev/null)" ]]
}

install_plugin() {
    local plugin_name=$1
    local repo_url=$2
    local plugin_dir="$PLUGINS_DIR/$plugin_name.yazi"

    if [[ -e "$plugin_dir" ]]; then
        echo "Removing existing $plugin_name plugin..."
        rm -rf "$plugin_dir"
    fi

    echo "Installing plugin $plugin_name..."
    git clone --depth 1 --single-branch --no-tags --quiet \
        "$repo_url" "$plugin_dir"
    rm -rf "$plugin_dir/.git"
}

install_plugin_local() {
    local plugin_name=$1
    local plugin_dir="$PLUGINS_DIR/$plugin_name.yazi"
    local source_dir="$TEMP_PLUGINS_DIR/$plugin_name.yazi"

    if [[ -e "$plugin_dir" ]]; then
        rm -rf "$plugin_dir"
    fi

    echo "Installing plugin $plugin_name..."
    cp -r "$source_dir" "$plugin_dir"
}

main() {
    declare -a dirs=(
        "$PLUGINS_DIR"
        "$FLAVORS_DIR"
    )

    for dir in "${dirs[@]}"; do
        mkdir -p "$dir"
    done

    trap cleanup EXIT

    if is_directory_empty "$TEMP_PLUGINS_DIR"; then
        echo "Downloading plugins repository..."
        git clone --depth 1 --single-branch --no-tags --quiet \
            "$YAZI_PLUGINS_REPO" "$TEMP_PLUGINS_DIR"
        rm -rf "$TEMP_PLUGINS_DIR/.git"
    fi

    declare -a official_plugins=(
        "diff"
        "full-border"
        "smart-enter"
        "smart-paste"
        "git"
    )

    for plugin in "${official_plugins[@]}"; do
        install_plugin_local "$plugin"
    done

    declare -A external_plugins=(
      ["system-clipboard"]="https://github.com/orhnk/system-clipboard.yazi.git"
      ["starship"]="https://github.com/Rolv-Apneseth/starship.yazi.git"
    )

    for plugin_name in "${!external_plugins[@]}"; do
        install_plugin "$plugin_name" "${external_plugins[$plugin_name]}"
    done
}

main "$@"
