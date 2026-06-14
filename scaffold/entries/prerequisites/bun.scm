(library
  (entries prerequisites bun)
  (export bun-tool)
  (import
    (rnrs)
    (scaffold catalog)
    (scaffold extensions app winget)
    (scaffold extensions support download))

  (doc-next (hidden) (summary "Create the Bun prerequisite tool."))

  (define (bun-tool)
    (tool
      "bun"
      (package
        (field
          'platforms
          (arr
            (remote-bash-installer/platform
              'macos
              "bun"
              "https://bun.sh/install"
              (arr "BUN_INSTALL={{ home }}/.cache/.bun")
              (arr)
              "{{ home }}/.cache/.bun")
            (remote-bash-installer/platform
              'linux
              "bun"
              "https://bun.sh/install"
              (arr "BUN_INSTALL={{ home }}/.cache/.bun")
              (arr)
              "{{ home }}/.cache/.bun")
            (winget/package-platform "Oven-sh.Bun"))))
      (field 'bins (arr (bin "bun") (bin "bunx")))))

  (moduledoc (summary "Bun prerequisite tool definition.") (group "Dotfiles tools")))
