(library
  (entries local cargo)
  (export repo-cargo-tools)
  (import (rnrs) (scaffold catalog) (scaffold extensions ecosystem cargo))

  (doc-next
    (hidden)
    (summary
      "Create a repo-local Cargo tool that installs without refreshing crates.io."))

  (define (repo-cargo-tool name path . fields)
    (tool/override
      (apply cargo/tool name path fields)
      (lambda (base)
        (object
          (field
            'action
            (build
              (field 'path path)
              (field 'argv (cargo/install-argv "{{ source_dir }}" (arr "--offline")))))))))

  (doc-next
    (hidden)
    (summary "Return tools built from Cargo packages in this repository."))

  (define (repo-cargo-tools)
    (list
      (repo-cargo-tool
        "gh-hide-comment"
        "packages/gh-hide-comment"
        (field 'platforms (arr "macos" "linux" "windows"))
        (field 'bins (arr (bin/version "gh-hide-comment" "--version")))
        (depends "rustup"))
      (repo-cargo-tool
        "system-run-mcp"
        "packages/system-run-mcp"
        (field 'platforms (arr "macos" "linux"))
        (field
          'bins
          (arr
            (bin/version "system-run-mcp" "--version")
            (bin/version "system-runner" "--version")))
        (depends "rustup"))
      (repo-cargo-tool
        "http-fixture"
        "packages/http-fixture"
        (field 'platforms (arr "macos"))
        (field 'bins (arr (bin/version "http-fixture" "--version")))
        (depends "rustup"))
      (repo-cargo-tool
        "lsp-diagnostic-filter"
        "packages/lsp-diagnostic-filter"
        (field 'platforms (arr "macos" "linux"))
        (field 'bins (arr (bin/version "nushell-lsp-filter" "--version")))
        (depends "rustup"))
      (repo-cargo-tool
        "zellij-theme-tools"
        "packages/zellij-theme-tools"
        (field 'platforms (arr "macos" "linux"))
        (field 'bins (arr (bin/version "zellij-theme-run" "--version")))
        (depends "rustup"))
      (repo-cargo-tool
        "chezmoi-support"
        "crates/chezmoi"
        (field 'platforms (arr "macos" "linux" "windows"))
        (depends "rustup"))
      (repo-cargo-tool
        "lenovo-con-mode"
        "packages/lenovo-con-mode"
        (field 'platforms (arr "linux" "windows"))
        (depends "rustup"))))

  (moduledoc
    (summary "Repo-local Cargo package tool definitions.")
    (group "Dotfiles tools")))
