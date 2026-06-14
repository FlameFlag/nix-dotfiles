(library
  (entries prerequisites node)
  (export node-tool)
  (import
    (rnrs)
    (installers macos node)
    (scaffold catalog)
    (scaffold extensions app winget)
    (scaffold extensions distro apt)
    (scaffold extensions distro dnf)
    (scaffold extensions distro pacman))

  (doc-next (hidden) (summary "Create the Node.js and npm prerequisite tool."))

  (define (node-tool)
    (tool
      "node"
      (package
        (field
          'platforms
          (arr
            (apt/package-platform
              "nodejs"
              (field
                'install-argvs
                (arr (apt-get/install-argv "nodejs") (apt-get/install-argv "npm"))))
            (dnf/package-platform "nodejs")
            (pacman/package-platform
              "nodejs"
              (field
                'install-argvs
                (arr (pacman/install-argv "nodejs") (pacman/install-argv "npm"))))
            (node-latest-platform (predicate 'macos 'aarch64) "arm64")
            (node-latest-platform (predicate 'macos 'x86_64) "x64")
            (winget/package-platform "OpenJS.NodeJS"))))
      (field 'bins (arr (bin "node") (bin "npm") (bin "npx")))))

  (moduledoc (summary "Node.js prerequisite tool definition.") (group "Dotfiles tools")))
