(library
  (entries apps scaffold-vscode-extension)
  (export scaffold-vscode-extension-tool)
  (import (rnrs) (scaffold catalog) (scaffold extensions support download))

  (doc-next (hidden) (summary "Create a platform that installs the rolling VSIX."))

  (define (scaffold-vscode-extension/platform predicate-value)
    (let
      ((vsix-dir (tool-cache-dir "scaffold-vscode"))
        (vsix-path
          (string-append
            (tool-cache-dir "scaffold-vscode")
            "/scaffold-vscode-rolling.vsix")))
      (package/platform-argvs
        predicate-value
        (arr "code" "curl" "mkdir")
        (arr
          (arr "mkdir" "-p" vsix-dir)
          (arr
            "curl"
            "-fsSL"
            "--retry"
            "3"
            "-o"
            vsix-path
            "https://github.com/FlameFlag/scaffold/releases/download/rolling/scaffold-vscode-rolling.vsix")
          (arr "code" "--install-extension" vsix-path "--force")))))

  (doc-next
    (summary
      "Create the Scaffold Scheme VS Code extension tool installed from the rolling VSIX."))

  (define (scaffold-vscode-extension-tool)
    (tool
      "scaffold-vscode-extension"
      (package
        (field
          'platforms
          (arr
            (scaffold-vscode-extension/platform 'macos)
            (scaffold-vscode-extension/platform 'linux))))
      (field
        'checks
        (arr
          (host/check
            'macos
            (arr "sh" "-c" "code --list-extensions | grep -Fx scaffold.scaffold-scheme"))
          (host/check
            'linux
            (arr "sh" "-c" "code --list-extensions | grep -Fx scaffold.scaffold-scheme"))))
      (meta
        (home-page "https://github.com/FlameFlag/scaffold")
        (description "Scheme-driven system scaffolding CLI"))))

  (moduledoc
    (summary "Scaffold Scheme VS Code extension tool definition.")
    (group "Dotfiles tools")))
