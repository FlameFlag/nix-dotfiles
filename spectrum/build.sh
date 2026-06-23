#!/usr/bin/env bash
# shellcheck shell=bash
set -ouex pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
CTX_DIR=${CTX_DIR:-$SCRIPT_DIR}
SPECTRUM_LIB_DIR=${SPECTRUM_LIB_DIR:-$CTX_DIR/lib}
SPECTRUM_SCRIPTS_DIR=${SPECTRUM_SCRIPTS_DIR:-$CTX_DIR/scripts}
export CTX_DIR SPECTRUM_LIB_DIR SPECTRUM_SCRIPTS_DIR

# shellcheck source=lib/common.sh
source -p "$SPECTRUM_LIB_DIR" common.sh
source_spectrum_lib repos
source_spectrum_lib github-releases
source_spectrum_lib archive-install
source_spectrum_lib release-rpms
source_spectrum_lib release-binaries
source_spectrum_lib system
source_spectrum_lib packages

# shellcheck source=scripts/repositories.sh
source -p "$SPECTRUM_SCRIPTS_DIR" repositories.sh
# shellcheck source=scripts/release-rpms.sh
source -p "$SPECTRUM_SCRIPTS_DIR" release-rpms.sh
# shellcheck source=scripts/release-binaries.sh
source -p "$SPECTRUM_SCRIPTS_DIR" release-binaries.sh
# shellcheck source=scripts/system.sh
source -p "$SPECTRUM_SCRIPTS_DIR" system.sh

require_arg_count 0 0 "$@"
require_bash_version 4 3
trap cleanup_temp_dirs EXIT
resolve_dnf_cmd

install_spectrum_rpm_repositories
SPECTRUM_FEDORA_REQUIRED_PACKAGES=()
SPECTRUM_FEDORA_OPTIONAL_PACKAGES=()
read_spectrum_package_manifest "${CTX_DIR}/packages.toml" required SPECTRUM_FEDORA_REQUIRED_PACKAGES
read_spectrum_package_manifest "${CTX_DIR}/packages.toml" optional SPECTRUM_FEDORA_OPTIONAL_PACKAGES
dnf_install_no_weak_deps "${SPECTRUM_FEDORA_REQUIRED_PACKAGES[@]}"
dnf_install_optional_no_weak_deps "${SPECTRUM_FEDORA_OPTIONAL_PACKAGES[@]}"
install_spectrum_release_rpms
install_spectrum_release_binaries

configure_spectrum_system
clean_dnf_metadata
