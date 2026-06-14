(library
  (installers macos node)
  (export node-latest-platform)
  (import (rnrs) (scaffold catalog) (scaffold extensions support download))

  (doc-next
    (summary "Create a macOS installer for the latest Node.js dist tarball.")
    (param 'node-arch "Node.js macOS archive architecture, such as `arm64` or `x64`."))

  (define (node-latest-platform predicate-value node-arch)
    (generated-shell-platform
      predicate-value
      (arr "curl" "head" "ln" "mkdir" "mv" "rm" "sed" "tar")
      (string-append
        (sh-set "root" (tool-cache-dir "node"))
        (sh-set "bin_dir" "{{ bin_dir }}")
        (sh-set "node_arch" node-arch)
        "version=$(curl -fsSL --retry 3 https://nodejs.org/dist/index.json | sed -n 's/.*\"version\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' | head -n 1)\n"
        "root_name=node-${version}-darwin-${node_arch}\n"
        "asset=${root_name}.tar.xz\n"
        "archive=${root}/${asset}\n"
        "extract_dir=${root}/extract\n"
        "install_dir=${root}/${root_name}\n"
        "mkdir -p \"${root}\" \"${bin_dir}\"\n"
        "curl -fsSL --retry 3 -o \"${archive}\" \"https://nodejs.org/dist/${version}/${asset}\"\n"
        "rm -rf \"${extract_dir}\" \"${install_dir}\"\n"
        "mkdir -p \"${extract_dir}\"\n"
        "tar -xJf \"${archive}\" -C \"${extract_dir}\"\n"
        "mv \"${extract_dir}/${root_name}\" \"${install_dir}\"\n"
        "ln -sfn \"${install_dir}/bin/node\" \"${bin_dir}/node\"\n"
        "ln -sfn \"${install_dir}/bin/npm\" \"${bin_dir}/npm\"\n"
        "ln -sfn \"${install_dir}/bin/npx\" \"${bin_dir}/npx\"\n")))

  (moduledoc
    (summary "macOS Node.js latest-release installer helper.")
    (group "Dotfiles platforms")))
