(library
  (installers macos app-bundle)
  (export zip-app-bin-platform)
  (import (rnrs) (installers cache) (scaffold catalog))

  (doc-next
    (summary "Create a macOS installer for an app zip with a CLI shim inside it.")
    (param 'url "Archive URL. This may be a stable latest endpoint.")
    (param 'app-name "App bundle name inside the archive.")
    (param 'bin-relative-path "CLI path relative to the app bundle."))

  (define
    (zip-app-bin-platform
      predicate-value
      tool-name
      url
      archive-name
      app-name
      bin-relative-path
      bin-name)
    (let*
      ((root (tool-cache-dir tool-name))
        (archive (downloaded-archive-path tool-name archive-name))
        (extract-dir (archive-extract-dir tool-name))
        (app-path (string-append root "/" app-name)))
      (package/platform-argvs
        predicate-value
        (arr "curl" "ditto" "ln" "mkdir" "rm")
        (arr
          (arr "mkdir" "-p" root "{{ bin_dir }}")
          (arr "curl" "-fsSL" "--retry" "3" "-o" archive url)
          (arr "rm" "-rf" extract-dir app-path)
          (arr "mkdir" "-p" extract-dir)
          (arr "ditto" "-x" "-k" archive extract-dir)
          (arr "ditto" (string-append extract-dir "/" app-name) app-path)
          (arr
            "ln"
            "-sfn"
            (string-append app-path "/" bin-relative-path)
            (string-append "{{ bin_dir }}/" bin-name))))))

  (moduledoc
    (summary "macOS application archive installer helpers.")
    (group "Dotfiles platforms")))
