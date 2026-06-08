(library
  (entries ecosystem python)
  (export python-tools)
  (import (rnrs) (scaffold catalog) (scaffold extensions ecosystem uv))

  (doc-next (hidden) (summary "Return Python CLI tools installed through uv."))

  (define (python-tools)
    (list
      (uv/tool "yt-dlp" (depends "uv"))
      (uv/tool "ruff" (depends "uv"))
      (uv/tool "ty" (depends "uv"))))

  (moduledoc
    (summary "uv-managed Python CLI tool definitions.")
    (group "Dotfiles tools")))
