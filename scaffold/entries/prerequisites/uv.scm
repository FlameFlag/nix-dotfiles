(library
  (entries prerequisites uv)
  (export uv-tool)
  (import
    (rnrs)
    (scaffold catalog)
    (scaffold extensions app winget)
    (scaffold extensions distro dnf)
    (scaffold extensions distro pacman)
    (scaffold extensions support download))

  (doc-next (hidden) (summary "Create the uv and uvx prerequisite tool."))

  (define (uv-tool)
    (tool
      "uv"
      (package
        (field
          'platforms
          (arr
            (dnf/package-platform "uv")
            (pacman/package-platform "uv")
            (remote-bash-installer/platform
              'linux
              "uv"
              "https://astral.sh/uv/install.sh"
              (arr "UV_INSTALL_DIR={{ bin_dir }}")
              (arr))
            (remote-bash-installer/platform
              'macos
              "uv"
              "https://astral.sh/uv/install.sh"
              (arr "UV_INSTALL_DIR={{ bin_dir }}")
              (arr))
            (winget/package-platform "astral-sh.uv"))))
      (field 'bins (arr (bin "uv") (bin "uvx")))))

  (moduledoc (summary "uv prerequisite tool definition.") (group "Dotfiles tools")))
