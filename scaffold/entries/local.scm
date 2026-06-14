(library
  (entries local)
  (export local/tools)
  (import
    (rnrs)
    (scaffold catalog)
    (entries local cargo)
    (entries local kanata)
    (entries local scaffold))

  (moduledoc
    (summary "Repo-local and personally pinned tools in the Scaffold catalog.")
    (group "Dotfiles tools"))

  (doc-next
    (summary "Return tools built from this repo or from personal upstream forks.")
    (returns "List of Scaffold tool objects."))

  (define (local/tools)
    (append (list (kanata-tool) (scaffold-tool)) (repo-cargo-tools))))
