(library
  (entries local scaffold)
  (export scaffold-tool)
  (import (rnrs) (scaffold catalog))

  (doc-next
    (summary
      "Create a macOS package platform that installs Scaffold from the rolling release asset."))

  (define (scaffold/rolling-platform predicate-value asset)
    (package/platform-argvs
      predicate-value
      (arr "curl" "install" "mkdir" "tar")
      (arr
        (arr
          "mkdir"
          "-p"
          "{{ home }}/.local/share/scaffold/tools/scaffold/latest"
          "{{ home }}/.local/bin")
        (arr
          "curl"
          "-fsSL"
          "--retry"
          "3"
          "-o"
          "{{ home }}/.local/share/scaffold/tools/scaffold/latest/{{ package }}.tar.gz"
          "https://github.com/FlameFlag/scaffold/releases/download/rolling/{{ package }}.tar.gz")
        (arr
          "tar"
          "-xzf"
          "{{ home }}/.local/share/scaffold/tools/scaffold/latest/{{ package }}.tar.gz"
          "-C"
          "{{ home }}/.local/share/scaffold/tools/scaffold/latest")
        (arr
          "install"
          "-m"
          "0755"
          "{{ home }}/.local/share/scaffold/tools/scaffold/latest/{{ package }}/scaffold"
          "{{ home }}/.local/bin/scaffold"))
      (field 'name asset)))

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
      (field 'platforms (arr "macos"))
      (field 'bins (arr (bin "scaffold")))
      (meta
        (home-page "https://github.com/FlameFlag/scaffold")
        (description "Scheme-driven system scaffolding CLI"))))

  (moduledoc
    (summary "Scaffold self-installing tool definition.")
    (group "Dotfiles tools")))
