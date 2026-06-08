(library
  (entries ecosystem)
  (export ecosystem/tools)
  (import
    (rnrs)
    (scaffold catalog)
    (entries ecosystem bun)
    (entries ecosystem nushell)
    (entries ecosystem python)
    (entries ecosystem yt-dlp-script))

  (moduledoc
    (summary "Language and CLI ecosystem tools in the personal Scaffold catalog.")
    (group "Dotfiles tools"))

  (doc-next
    (summary
      "Return language ecosystem tools installed by Bun, uv, and related package managers.")
    (returns "List of Scaffold tool objects."))

  (define (ecosystem/tools)
    (append
      (append (bun-global-tools) (python-tools))
      (list (nushell-tool) (yt-dlp-script-tool)))))
