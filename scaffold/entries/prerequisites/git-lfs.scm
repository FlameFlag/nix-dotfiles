(library
  (entries prerequisites git-lfs)
  (export git-lfs-tool)
  (import
    (rnrs)
    (scaffold catalog)
    (scaffold extensions app winget)
    (scaffold extensions distro apt)
    (scaffold extensions distro dnf)
    (scaffold extensions distro pacman)
    (scaffold extensions source github))

  (doc-next (hidden) (summary "Create the Git LFS prerequisite tool."))

  (define (git-lfs-tool)
    (tool
      "git-lfs"
      (package
        (field
          'platforms
          (arr
            (apt/package-platform "git-lfs")
            (dnf/package-platform "git-lfs")
            (pacman/package-platform "git-lfs")
            (github/latest-zip-bin-platform
              (predicate 'macos 'aarch64)
              "git-lfs"
              "git-lfs/git-lfs"
              "git-lfs-darwin-arm64-v${version}.zip"
              "git-lfs-${version}/git-lfs"
              "git-lfs")
            (github/latest-zip-bin-platform
              (predicate 'macos 'x86_64)
              "git-lfs"
              "git-lfs/git-lfs"
              "git-lfs-darwin-amd64-v${version}.zip"
              "git-lfs-${version}/git-lfs"
              "git-lfs")
            (winget/package-platform "GitHub.GitLFS"))))
      (field 'bins (arr (bin "git-lfs")))))

  (moduledoc (summary "Git LFS prerequisite tool definition.") (group "Dotfiles tools")))
