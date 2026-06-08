(library
  (entries ecosystem bun)
  (export bun-global-tools)
  (import (rnrs) (scaffold catalog) (scaffold extensions ecosystem bun))

  (doc-next
    (hidden)
    (summary "Return Bun global tools installed after Bun is present."))

  (define (bun-global-tools)
    (list
      (bun/global-tool "codex" "@openai/codex" "codex" (depends "bun"))
      (bun/global-tool
        "pi-coding-agent"
        "@earendil-works/pi-coding-agent"
        "pi"
        (depends "bun"))))

  (moduledoc (summary "Bun global CLI tool definitions.") (group "Dotfiles tools")))
