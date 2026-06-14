(library
  (entries apps one-password)
  (export one-password-tool)
  (import
    (rnrs)
    (installers linux one-password)
    (installers macos one-password)
    (scaffold catalog)
    (scaffold extensions app winget))

  (doc-next (hidden) (summary "Create the 1Password desktop and CLI application tool."))

  (define (one-password-tool)
    (tool
      "1password"
      (package
        (field
          'platforms
          (arr
            (apt-platform)
            (rpm-platform
              (arr "dnf")
              (arr "sudo" "dnf" "install" "-y" "1password" "1password-cli"))
            (rpm-platform
              (arr "rpm-ostree")
              (arr
                "sudo"
                "rpm-ostree"
                "install"
                "--idempotent"
                "-y"
                "1password"
                "1password-cli"))
            (package/platform-argvs
              'windows
              (arr "winget")
              (arr
                (winget/install-argv "AgileBits.1Password")
                (winget/install-argv "AgileBits.1Password.CLI"))
              (field 'name "1password"))
            (one-password-latest-platform (predicate 'macos 'aarch64) "arm64")
            (one-password-latest-platform (predicate 'macos 'x86_64) "amd64"))))
      (field 'bins (arr (bin/version "op" "--version")))
      (field 'paths (arr (tool/path "macos" "/Applications/1Password.app")))
      (field 'verify-after-install #f)))

  (moduledoc
    (summary "1Password application and CLI tool definition.")
    (group "Dotfiles tools")))
