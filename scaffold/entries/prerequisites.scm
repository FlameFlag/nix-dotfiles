(library
  (entries prerequisites)
  (export prerequisites/tools)
  (import
    (rnrs)
    (scaffold catalog)
    (entries prerequisites bun)
    (entries prerequisites chezmoi)
    (entries prerequisites go)
    (entries prerequisites git)
    (entries prerequisites git-lfs)
    (entries prerequisites node)
    (entries prerequisites powershell)
    (entries prerequisites rustup)
    (entries prerequisites uv))

  (moduledoc
    (summary "Prerequisite tools expressed as Scaffold catalog tools.")
    (group "Dotfiles tools"))

  (doc-next
    (summary
      "Return base tools needed before the rest of the personal catalog can install.")
    (returns "List of Scaffold tool objects."))

  (define (prerequisites/tools)
    (list
      (chezmoi-tool)
      (go-tool)
      (powershell-tool)
      (git-tool)
      (git-lfs-tool)
      (uv-tool)
      (rustup-tool)
      (node-tool)
      (bun-tool))))
