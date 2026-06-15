(library
  (entries local go)
  (export repo-go-tools)
  (import (rnrs) (scaffold catalog))

  (doc-next (hidden) (summary "Create a repo-local Go install platform."))

  (define (go-install-platform predicate-value commands)
    (package/platform
      predicate-value
      (arr "env" "go")
      (apply arr (append (list "env" "GOBIN={{ bin_dir }}" "go" "install") commands))))

  (doc-next (hidden) (summary "Create a repo-local Go command tool."))

  (define (repo-go-tool name commands platforms bins)
    (tool
      name
      (package
        (field
          'platforms
          (apply
            arr
            (map (lambda (platform) (go-install-platform platform commands)) platforms))))
      (field 'bins bins)))

  (doc-next
    (hidden)
    (summary "Return tools built from Go commands in this repository."))

  (define (repo-go-tools)
    (list
      (repo-go-tool
        "system-run-mcp"
        (list "./cmd/system-run-mcp" "./cmd/system-runner")
        (list 'macos 'linux)
        (arr
          (bin/version "system-run-mcp" "--version")
          (bin/version "system-runner" "--version")))
      (repo-go-tool
        "http-fixture"
        (list "./cmd/http-fixture")
        (list 'macos)
        (arr (bin/version "http-fixture" "--version")))
      (repo-go-tool
        "lsp-diagnostic-filter"
        (list "./cmd/lsp-diagnostic-filter")
        (list 'macos 'linux)
        (arr (bin/version "lsp-diagnostic-filter" "--version")))
      (repo-go-tool
        "zellij-theme-tools"
        (list "./cmd/zellij-theme-run")
        (list 'macos 'linux)
        (arr (bin/version "zellij-theme-run" "--version")))
      (repo-go-tool
        "chezmoi-support"
        (list "./cmd/chezmoi-support")
        (list 'macos 'linux)
        (arr (bin/version "chezmoi-support" "--version")))
      (repo-go-tool
        "nd-tools"
        (list "./cmd/nd-tools")
        (list 'macos 'linux 'windows)
        (arr (bin/version "nd-tools" "--version")))
      (repo-go-tool
        "lenovo-con-mode"
        (list "./cmd/lenovo-con-mode")
        (list 'linux)
        (arr (bin/version "lenovo-con-mode" "--version")))))

  (moduledoc
    (summary "Repo-local Go command tool definitions.")
    (group "Dotfiles tools")))
