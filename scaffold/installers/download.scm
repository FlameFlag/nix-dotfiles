(library
  (installers download)
  (export
    download-bin/platform
    generated-shell-platform
    remote-bash-installer/platform
    sh-set)
  (import (rnrs) (installers cache) (scaffold catalog))

  (doc-next (hidden) (summary "Return a shell assignment with a single-quoted value."))

  (define (sh-set name value) (string-append name "='" value "'\n"))

  (doc-next (hidden) (summary "Create a platform from a generated shell body."))

  (define (generated-shell-platform predicate-value requires body)
    (package/platform
      predicate-value
      requires
      (arr "sh" "-c" (string-append "set -eu\n" body))))

  (doc-next
    (summary
      "Create a platform that downloads and executes an upstream Bash installer.")
    (param 'tool-name "Tool cache directory name.")
    (param 'url "Installer script URL.")
    (param 'env-vars "Vector of `NAME=value` entries passed through `env`.")
    (param 'args "Vector of arguments passed to the downloaded installer.")
    (param 'extra-dir "Optional directories to create before running the installer."))

  (define
    (remote-bash-installer/platform
      predicate-value
      tool-name
      url
      env-vars
      args
      .
      extra-dirs)
    (let
      ((root (tool-cache-dir tool-name))
        (script-path (string-append (tool-cache-dir tool-name) "/install.sh")))
      (package/platform-argvs
        predicate-value
        (arr "bash" "curl" "env" "mkdir")
        (list->vector
          (list
            (list->vector (append (list "mkdir" "-p" root "{{ bin_dir }}") extra-dirs))
            (arr "curl" "-fsSL" "--retry" "3" "-o" script-path url)
            (list->vector
              (append
                (list "env")
                (append
                  (vector->list env-vars)
                  (append (list "bash" script-path) (vector->list args))))))))))

  (doc-next
    (summary
      "Create a platform that downloads a file directly into `bin_dir` and chmods it executable.")
    (param 'url "Source file URL.")
    (param 'bin-name "Installed executable name."))

  (define (download-bin/platform predicate-value url bin-name)
    (package/platform-argvs
      predicate-value
      (arr "chmod" "curl" "mkdir")
      (arr
        (arr "mkdir" "-p" "{{ bin_dir }}")
        (arr
          "curl"
          "-fsSL"
          "--retry"
          "3"
          "-o"
          (string-append "{{ bin_dir }}/" bin-name)
          url)
        (arr "chmod" "+x" (string-append "{{ bin_dir }}/" bin-name)))))

  (moduledoc
    (summary "Command-backed download and shell installer platform helpers.")
    (group "Dotfiles platforms")))
