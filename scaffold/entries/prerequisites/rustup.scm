(library
  (entries prerequisites rustup)
  (export rustup-tool)
  (import
    (rnrs)
    (scaffold catalog)
    (scaffold extensions app winget)
    (scaffold extensions support download))

  (doc-next (hidden) (summary "Create the Rust toolchain prerequisite tool."))

  (define (rustup-tool)
    (tool
      "rustup"
      (package
        (field
          'platforms
          (arr
            (remote-bash-installer/platform
              'macos
              "rustup"
              "https://sh.rustup.rs"
              (arr)
              (arr
                "-y"
                "--profile"
                "default"
                "--component"
                "rustfmt"
                "--component"
                "clippy"
                "--component"
                "rust-analyzer"
                "--component"
                "rust-src"))
            (remote-bash-installer/platform
              'linux
              "rustup"
              "https://sh.rustup.rs"
              (arr)
              (arr
                "-y"
                "--profile"
                "default"
                "--component"
                "rustfmt"
                "--component"
                "clippy"
                "--component"
                "rust-analyzer"
                "--component"
                "rust-src"))
            (winget/package-platform "Rustlang.Rustup"))))
      (field
        'bins
        (arr
          (bin "rustup")
          (bin "cargo")
          (bin "rustc")
          (bin "rustfmt")
          (bin "cargo-clippy")
          (bin "rust-analyzer")))))

  (moduledoc (summary "Rustup prerequisite tool definition.") (group "Dotfiles tools")))
