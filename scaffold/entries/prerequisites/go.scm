(library
  (entries prerequisites go)
  (export go-tool)
  (import
    (rnrs)
    (scaffold catalog)
    (scaffold extensions app winget)
    (scaffold extensions support download))

  (doc-next (hidden) (summary "Create an official Go tarball install platform."))

  (define (go/tarball-platform predicate-value goos goarch)
    (generated-shell-platform
      predicate-value
      (arr "curl" "head" "ln" "mkdir" "mv" "rm" "sed" "tar")
      (string-append
        (sh-set "root" (tool-cache-dir "go"))
        (sh-set "bin_dir" "{{ bin_dir }}")
        (sh-set "goos" goos)
        (sh-set "goarch" goarch)
        "version=$(curl -fsSL --retry 3 'https://go.dev/dl/?mode=json' | sed -n 's/.*\"version\"[[:space:]]*:[[:space:]]*\"\\([^\"]*\\)\".*/\\1/p' | head -n 1)\n"
        "root_name=${version}.${goos}-${goarch}\n"
        "asset=${root_name}.tar.gz\n"
        "archive=${root}/${asset}\n"
        "extract_dir=${root}/extract\n"
        "install_dir=${root}/${root_name}\n"
        "mkdir -p \"${root}\" \"${bin_dir}\"\n"
        "curl -fsSL --retry 3 -o \"${archive}\" \"https://go.dev/dl/${asset}\"\n"
        "rm -rf \"${extract_dir}\" \"${install_dir}\"\n"
        "mkdir -p \"${extract_dir}\"\n"
        "tar -xzf \"${archive}\" -C \"${extract_dir}\"\n"
        "mv \"${extract_dir}/go\" \"${install_dir}\"\n"
        "ln -sfn \"${install_dir}/bin/go\" \"${bin_dir}/go\"\n"
        "ln -sfn \"${install_dir}/bin/gofmt\" \"${bin_dir}/gofmt\"\n")))

  (doc-next (hidden) (summary "Create the Go prerequisite tool."))

  (define (go-tool)
    (tool
      "go"
      (package
        (field
          'platforms
          (arr
            (go/tarball-platform (predicate 'macos 'aarch64) "darwin" "arm64")
            (go/tarball-platform (predicate 'macos 'x86_64) "darwin" "amd64")
            (go/tarball-platform (predicate 'linux 'aarch64) "linux" "arm64")
            (go/tarball-platform (predicate 'linux 'x86_64) "linux" "amd64")
            (winget/package-platform "GoLang.Go"))))
      (field 'bins (arr (bin "go") (bin "gofmt")))))

  (moduledoc (summary "Go prerequisite tool definition.") (group "Dotfiles tools")))
