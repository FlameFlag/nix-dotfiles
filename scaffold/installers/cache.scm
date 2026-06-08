(library
  (installers cache)
  (export archive-extract-dir downloaded-archive-path tool-cache-dir)
  (import (rnrs) (scaffold catalog))

  (doc-next (hidden) (summary "Return the per-tool Scaffold cache directory."))

  (define (tool-cache-dir tool-name)
    (string-append "{{ home }}/.local/share/scaffold/tools/" tool-name "/latest"))

  (doc-next (hidden) (summary "Return the cached path for a downloaded archive."))

  (define (downloaded-archive-path tool-name archive-name)
    (string-append (tool-cache-dir tool-name) "/" archive-name))

  (doc-next (hidden) (summary "Return the temporary archive extraction directory."))

  (define (archive-extract-dir tool-name)
    (string-append (tool-cache-dir tool-name) "/extract"))

  (moduledoc
    (summary "Shared Scaffold tool cache path helpers.")
    (group "Dotfiles platforms")))
