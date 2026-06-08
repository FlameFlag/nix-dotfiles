(library
  (entries ecosystem nushell)
  (export nushell-tool)
  (import
    (rnrs)
    (installers macos github-release)
    (scaffold catalog)
    (scaffold extensions app winget)
    (scaffold extensions distro apt)
    (scaffold extensions distro dnf)
    (scaffold extensions distro pacman))

  (doc-next (hidden) (summary "Create the Nushell tool."))

  (define (nushell-tool)
    (tool
      "nushell"
      (package
        (field
          'platforms
          (arr
            (apt/package-platform "nushell")
            (dnf/package-platform "nushell")
            (pacman/package-platform "nushell")
            (github-latest-targz-bin-platform
              (predicate 'macos 'aarch64)
              "nushell"
              "nushell/nushell"
              "nu-${version}-aarch64-apple-darwin.tar.gz"
              "nu-${version}-aarch64-apple-darwin/nu"
              "nu")
            (github-latest-targz-bin-platform
              (predicate 'macos 'x86_64)
              "nushell"
              "nushell/nushell"
              "nu-${version}-x86_64-apple-darwin.tar.gz"
              "nu-${version}-x86_64-apple-darwin/nu"
              "nu")
            (winget/package-platform "Nushell.Nushell"))))
      (field 'platforms (arr "macos" "linux" "windows"))
      (field 'bins (arr (bin "nu")))))

  (moduledoc (summary "Nushell tool definition.") (group "Dotfiles tools")))
