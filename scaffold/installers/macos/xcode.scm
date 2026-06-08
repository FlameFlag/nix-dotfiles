(library
  (installers macos xcode)
  (export xcode-command-line-tools-platform)
  (import (rnrs) (scaffold catalog))

  (doc-next
    (summary "Create a macOS installer that delegates Git to Apple Command Line Tools."))

  (define (xcode-command-line-tools-platform)
    (package/platform
      'macos
      (arr "sh" "xcode-select")
      (arr "sh" "-c" "xcode-select -p >/dev/null 2>&1 || xcode-select --install")))

  (moduledoc
    (summary "macOS Command Line Tools platform helper.")
    (group "Dotfiles platforms")))
