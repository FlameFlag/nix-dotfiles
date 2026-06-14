(library
  (installers macos one-password)
  (export one-password-latest-platform)
  (import (rnrs) (scaffold catalog) (scaffold extensions support download))

  (doc-next
    (summary "Create a macOS installer for the latest 1Password CLI zip.")
    (param
      'op-arch
      "1Password CLI macOS archive architecture, such as `arm64` or `amd64`."))

  (define (one-password-latest-platform predicate-value op-arch)
    (generated-shell-platform
      predicate-value
      (arr "curl" "ditto" "head" "install" "mkdir" "rm" "sed")
      (string-append
        (sh-set "root" (tool-cache-dir "1password"))
        (sh-set "bin_dir" "{{ bin_dir }}")
        (sh-set "op_arch" op-arch)
        "version=$(curl -fsSL --retry 3 'https://app-updates.agilebits.com/check/1/0/CLI2/en/2.0.0/N' | sed -n 's/.*\"version\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' | head -n 1)\n"
        "asset=op_darwin_${op_arch}_v${version}.zip\n"
        "archive=${root}/${asset}\n"
        "extract_dir=${root}/extract\n"
        "mkdir -p \"${root}\" \"${bin_dir}\"\n"
        "curl -fsSL --retry 3 -o \"${archive}\" \"https://cache.agilebits.com/dist/1P/op2/pkg/v${version}/${asset}\"\n"
        "rm -rf \"${extract_dir}\"\n"
        "mkdir -p \"${extract_dir}\"\n"
        "ditto -x -k \"${archive}\" \"${extract_dir}\"\n"
        "install -m 0755 \"${extract_dir}/op\" \"${bin_dir}/op\"\n")))

  (moduledoc
    (summary "macOS 1Password CLI latest-release installer helper.")
    (group "Dotfiles platforms")))
