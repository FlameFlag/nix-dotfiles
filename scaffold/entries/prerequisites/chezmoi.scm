(library
  (entries prerequisites chezmoi)
  (export chezmoi-tool)
  (import
    (rnrs)
    (installers download)
    (scaffold catalog)
    (scaffold extensions app winget)
    (scaffold extensions distro apt)
    (scaffold extensions distro dnf)
    (scaffold extensions distro pacman))

  (doc-next (hidden) (summary "Create the chezmoi prerequisite tool."))

  (define (chezmoi-tool)
    (tool
      "chezmoi"
      (package
        (field
          'platforms
          (arr
            (apt/package-platform "chezmoi")
            (dnf/package-platform "chezmoi")
            (pacman/package-platform "chezmoi")
            (remote-bash-installer/platform
              'macos
              "chezmoi"
              "https://get.chezmoi.io"
              (arr)
              (arr "-b" "{{ bin_dir }}"))
            (remote-bash-installer/platform
              'linux
              "chezmoi"
              "https://get.chezmoi.io"
              (arr)
              (arr "-b" "{{ bin_dir }}"))
            (winget/package-platform "twpayne.chezmoi"))))
      (field 'platforms (arr "macos" "linux" "windows"))
      (field 'bins (arr (bin "chezmoi")))))

  (moduledoc (summary "chezmoi prerequisite tool definition.") (group "Dotfiles tools")))
