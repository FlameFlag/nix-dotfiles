(library
  (entries prerequisites git)
  (export git-tool)
  (import
    (rnrs)
    (scaffold catalog)
    (scaffold extensions app winget)
    (scaffold extensions distro apt)
    (scaffold extensions distro dnf)
    (scaffold extensions distro pacman)
    (scaffold extensions platform macos))

  (doc-next (hidden) (summary "Create the Git prerequisite tool."))

  (define (git-tool)
    (tool
      "git"
      (package
        (field
          'platforms
          (arr
            (apt/package-platform "git")
            (dnf/package-platform "git")
            (pacman/package-platform "git")
            (xcode-command-line-tools-platform)
            (winget/package-platform "Git.Git"))))
      (field 'bins (arr (bin "git")))))

  (moduledoc (summary "Git prerequisite tool definition.") (group "Dotfiles tools")))
