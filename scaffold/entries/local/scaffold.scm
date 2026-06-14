(library
  (entries local scaffold)
  (export scaffold-tool)
  (import (rnrs) (scaffold catalog) (scaffold extensions support download))

  (doc-next
    (summary
      "Create a macOS package platform that installs Scaffold from the rolling release asset."))

  (define (scaffold/rolling-platform predicate-value asset)
    (let
      ((root (tool-cache-dir "scaffold"))
        (archive (string-append (tool-cache-dir "scaffold") "/{{ package }}.tar.gz")))
      (package/platform-argvs
        predicate-value
        (arr "curl" "install" "mkdir" "tar")
        (arr
          (arr "mkdir" "-p" root "{{ bin_dir }}")
          (arr
            "curl"
            "-fsSL"
            "--retry"
            "3"
            "-o"
            archive
            "https://github.com/FlameFlag/scaffold/releases/download/rolling/{{ package }}.tar.gz")
          (arr "tar" "-xzf" archive "-C" root)
          (arr
            "install"
            "-m"
            "0755"
            (string-append root "/{{ package }}/scaffold")
            "{{ bin_dir }}/scaffold"))
        (field 'name asset))))

  (doc-next
    (hidden)
    (summary "Create the Scaffold self-installing tool for macOS hosts."))

  (define (scaffold-tool)
    (tool
      "scaffold"
      (package
        (field
          'platforms
          (arr
            (scaffold/rolling-platform
              (predicate 'macos 'aarch64)
              "scaffold-rolling-aarch64-apple-darwin")
            (scaffold/rolling-platform
              (predicate 'macos 'x86_64)
              "scaffold-rolling-x86_64-apple-darwin"))))
      (field 'bins (arr (bin "scaffold")))
      (meta
        (home-page "https://github.com/FlameFlag/scaffold")
        (description "Scheme-driven system scaffolding CLI"))))

  (moduledoc
    (summary "Scaffold self-installing tool definition.")
    (group "Dotfiles tools")))
